const std = @import("std");
const llvm = @import("llvm");
const lexer = @import("lexer.zig");
const err = @import("error.zig");
const token = @import("token.zig");
const parser = @import("parser.zig");
const ast = @import("ast.zig");
const codegen = @import("codegen.zig");
const sema = @import("sema/semantics.zig");
const Options = @import("cli.zig").Options;

pub const Compiler = struct {
    allocator: std.mem.Allocator,
    errors: std.ArrayList(err.SourceError),
    source: []const u8,
    ast: ast.AST,
    sema: sema.Sema,
    ctx: llvm.LLVMContextRef,
    mod: llvm.LLVMModuleRef,
    opt: Options,

    pub fn init(allocator: std.mem.Allocator, source: []const u8, opt: Options) Compiler {
        return Compiler{
            .allocator = allocator,
            .errors = .empty,
            .source = source,
            .ast = undefined,
            .sema = undefined,
            .mod = undefined,
            .ctx = undefined,
            .opt = opt,
        };
    }

    pub fn jit(self: *Compiler) !void {
        // jit compilation
        if (std.mem.eql(u8, self.opt.target, "aarch64")) {
            llvm.LLVMInitializeAArch64TargetInfo();
            llvm.LLVMInitializeAArch64Target();
            llvm.LLVMInitializeAArch64TargetMC();
            llvm.LLVMInitializeAArch64AsmPrinter();
        } else if (std.mem.eql(u8, self.opt.target, "x86")) {
            llvm.LLVMInitializeX86TargetInfo();
            llvm.LLVMInitializeX86Target();
            llvm.LLVMInitializeX86TargetMC();
            llvm.LLVMInitializeX86AsmPrinter();
        } else {
            std.debug.print("{s} target is not currently supported\n", .{self.opt.target});
            return;
        }

        const builder = llvm.LLVMOrcCreateLLJITBuilder();
        if (builder == null) {
            std.debug.print("failed to create LLJIT builder\n", .{});
            return;
        }
        var j: llvm.LLVMOrcLLJITRef = null;
        _ = llvm.LLVMOrcCreateLLJIT(&j, builder);
        if (j == null) {
            std.debug.print("LLVM failed to create LLJIT\n", .{});
            return;
        }

        // get thread safe context for jit
        const tsctx = llvm.LLVMOrcCreateNewThreadSafeContextFromLLVMContext(self.ctx);
        const tsm = llvm.LLVMOrcCreateNewThreadSafeModule(self.mod, tsctx);
        const jd = llvm.LLVMOrcLLJITGetMainJITDylib(j);
        _ = llvm.LLVMOrcLLJITAddLLVMIRModule(j, jd, tsm);
        var addr: llvm.LLVMOrcExecutorAddress = undefined;
        _ = llvm.LLVMOrcLLJITLookup(j, &addr, @ptrCast("main"));
        const Main = @as(*const fn () callconv(.c) i32, @ptrFromInt(addr));
        const result = Main();

        std.debug.print("result = {}\n", .{result});
    }

    pub fn run(self: *Compiler) !void {
        if (self.opt.emit_tokens) {
            var tokens = try lexer.tokenize(self.allocator, self.source);
            defer tokens.deinit(self.allocator);

            std.debug.print("\nTokens:\n", .{});
            for (tokens.items) |tok| {
                std.debug.print("{d}:{d:<3} {s:<12} '{s}'\n", .{ tok.line, tok.col, @tagName(tok.type), tok.val });
            }
        }

        var p = parser.Parser.init(self.allocator, self.source, self);
        self.ast = try p.parse();

        if (self.opt.emit_ast) try self.ast.print();

        self.sema = sema.Sema.init(self);
        try self.sema.analyze();
        if (self.opt.sema) {
            try self.emitErrors();
        }

        if (self.opt.run_jit) {
            var c = codegen.Codegen.init(self.allocator, self);
            self.mod = try c.codegen();
            self.ctx = c.ctx;
            var error_message: [*c]u8 = null;
            const res = llvm.LLVMPrintModuleToFile(self.mod, "./corpus/codegen/dump.ll", &error_message);
            if (res != 0) {
                if (error_message) |msg| {
                    std.debug.print("LLVM: {s}\n", .{std.mem.span(msg)});
                    llvm.LLVMDisposeMessage(msg);
                }
            }

            if (self.opt.emit_ir) {
                const mod_str = llvm.LLVMPrintModuleToString(self.mod);
                std.debug.print("{s}\n", .{mod_str});
            }

            try self.jit();
            c.deinit();
        }

        self.sema.deinit();
        self.ast.deinit(self.allocator);
    }

    pub fn addError(self: *Compiler, msg: []const u8, severity: err.Severity, tok: token.Token) !void {
        const err_msg = try std.fmt.allocPrint(self.allocator, "{s} here but found {s}\n", .{ msg, tok.val });
        try self.errors.append(self.allocator, err.SourceError{
            .msg = err_msg,
            .severity = severity,
            .token = tok,
        });
    }

    pub fn add_sem_error(self: *Compiler, comptime fmt: []const u8, args: anytype, severity: err.Severity, tok: token.Token) !void {
        const err_msg = try std.fmt.allocPrint(self.allocator, fmt, args);
        try self.errors.append(self.allocator, err.SourceError{ .msg = err_msg, .severity = severity, .token = tok });
    }

    pub fn emitErrors(self: *Compiler) !void {
        for (self.errors.items) |e| {
            var l_count: usize = 1;
            var lines = std.mem.splitScalar(u8, self.source, '\n');
            while (lines.next()) |l| {
                if (l_count + 3 <= e.token.line) {
                    l_count += 1;
                    continue;
                } else if (l_count >= e.token.line + 3) {
                    break;
                } else if (l_count == e.token.line) {
                    std.debug.print("{d} | {s}", .{ l_count, l[0 .. e.token.col - 1] });
                    std.debug.print("{s}", .{l[e.token.col - 1 .. e.token.col + e.token.val.len - 1]});
                    std.debug.print("{s}\n", .{l[e.token.col + e.token.val.len - 1 ..]});
                    std.debug.print("    ", .{});
                    for (l[0 .. e.token.col - 1]) |_| {
                        std.debug.print(" ", .{});
                    }
                    for (l[e.token.col - 1 .. e.token.col + e.token.val.len - 1]) |_| {
                        std.debug.print("^", .{});
                    }
                    switch (e.severity) {
                        err.Severity.Error => {
                            std.debug.print(" \x1b[31m{s}\x1b[0m\n\n", .{e.msg});
                        },
                        err.Severity.Warn => {
                            std.debug.print(" \x1b[33m{s}\x1b[0m\n\n", .{e.msg});
                        },
                        err.Severity.Info => {
                            std.debug.print(" \x1b[36m{s}\x1b[0m\n\n", .{e.msg});
                        },
                    }
                } else {
                    std.debug.print("{d} | {s}\n", .{ l_count, l });
                }
                l_count += 1;
            }
        }
    }

    pub fn deinit(self: *Compiler) void {
        for (self.errors.items) |e| {
            self.allocator.free(e.msg);
        }
        self.errors.deinit(self.allocator);
    }
};
