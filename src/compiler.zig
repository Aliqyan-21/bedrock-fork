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

const log = std.log.scoped(.compiler);
const Error = error{ CompilerFail, JitError, MainFuncNotFound };

pub const JitRetType = union(enum) {
    i32: i32,
    f32: f32,
    f64: f64,
};

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

    pub fn jit(self: *Compiler) !JitRetType {
        const jit_builder = llvm.LLVMOrcCreateLLJITBuilder();
        if (jit_builder == null) {
            log.err("failed to create LLJIT builder\n", .{});
            return Error.JitError;
        }

        var j: llvm.LLVMOrcLLJITRef = null;
        var e = llvm.LLVMOrcCreateLLJIT(&j, jit_builder);
        if (e != null) {
            const err_ref = llvm.LLVMGetErrorMessage(e);
            log.err("{s}\n", .{err_ref});
            llvm.LLVMDisposeErrorMessage(err_ref);
            return Error.JitError;
        }

        const jd = llvm.LLVMOrcLLJITGetMainJITDylib(j);
        // add runtime mem
        const err_msg: [*c][*c]u8 = null;
        var obj_mem: llvm.LLVMMemoryBufferRef = undefined;
        _ = llvm.LLVMCreateMemoryBufferWithContentsOfFile("zig-out/memory.o", &obj_mem, err_msg);
        if (err_msg) |msg| {
            log.err("{s}\n", .{std.mem.span(msg)});
            llvm.LLVMDisposeMessage(msg);
            return Error.JitError;
        }

        e = llvm.LLVMOrcLLJITAddObjectFile(j, jd, obj_mem);
        if (e != null) {
            const err_ref = llvm.LLVMGetErrorMessage(e);
            log.err("{s}\n", .{err_ref});
            llvm.LLVMDisposeErrorMessage(err_ref);
            return Error.JitError;
        }

        const func = llvm.LLVMGetNamedFunction(self.mod, "main");
        if (func == null) {
            log.err("main func not found in the program\n", .{});
            return Error.MainFuncNotFound;
        }
        const func_type = llvm.LLVMGlobalGetValueType(func);
        const return_type = llvm.LLVMGetReturnType(func_type);

        // get thread safe context for jit
        const tsctx = llvm.LLVMOrcCreateNewThreadSafeContextFromLLVMContext(self.ctx);
        const tsm = llvm.LLVMOrcCreateNewThreadSafeModule(self.mod, tsctx);
        _ = llvm.LLVMOrcLLJITAddLLVMIRModule(j, jd, tsm);

        var addr: llvm.LLVMOrcExecutorAddress = undefined;
        _ = llvm.LLVMOrcLLJITLookup(j, &addr, @ptrCast("main"));

        switch (llvm.LLVMGetTypeKind(return_type)) {
            llvm.LLVMIntegerTypeKind => {
                const Main = @as(*const fn () callconv(.c) i32, @ptrFromInt(addr));
                const res = Main();
                log.debug("jit result: {}\n", .{res});
                return .{ .i32 = res };
            },
            llvm.LLVMFloatTypeKind => {
                const Main = @as(*const fn () callconv(.c) f32, @ptrFromInt(addr));
                const res = Main();
                log.debug("jit result: {}\n", .{res});
                return .{ .f32 = res };
            },
            llvm.LLVMDoubleTypeKind => {
                const Main = @as(*const fn () callconv(.c) f64, @ptrFromInt(addr));
                const res = Main();
                log.debug("jit result: {}\n", .{res});
                return .{ .f64 = res };
            },
            else => {
                log.err("ret type is not supported\n", .{});
                return Error.JitError;
            },
        }
    }

    pub fn run(self: *Compiler) !JitRetType {
        if (self.opt.emit_tokens) {
            var tokens = try lexer.tokenize(self.allocator, self.source);
            defer tokens.deinit(self.allocator);

            log.debug("\nTokens:\n", .{});
            for (tokens.items) |tok| {
                log.debug("{d}:{d:<3} {s:<12} '{s}'\n", .{ tok.line, tok.col, @tagName(tok.type), tok.val });
            }
        }

        var p = parser.Parser.init(self.allocator, self.source, self);
        self.ast = try p.parse();

        if (self.opt.emit_ast) try self.ast.print();

        var s_run = false;
        if (self.opt.sema) {
            self.sema = sema.Sema.init(self);
            try self.sema.analyze();
            s_run = true;
        }

        var r: JitRetType = .{ .i32 = 0 };
        if (self.opt.run_jit or self.opt.emit_ir) {
            var c = try codegen.Codegen.init(self.allocator, self);
            self.mod = try c.codegen();
            self.ctx = c.ctx;

            var err_msg: [*c]u8 = null;
            if (self.opt.emit_ir) {
                _ = llvm.LLVMPrintModuleToFile(self.mod, "./build/dump.ll", &err_msg);
                if (err_msg) |msg| {
                    log.err("{s}\n", .{std.mem.span(msg)});
                    llvm.LLVMDisposeMessage(msg);
                    return Error.CompilerFail;
                }
                const mod_str = llvm.LLVMPrintModuleToString(self.mod);
                log.debug("{s}\n", .{mod_str});
            }

            if (self.opt.emit_obj) {
                _ = llvm.LLVMTargetMachineEmitToFile(c.tm, c.mod, "./build/out.o", llvm.LLVMObjectFile, &err_msg);
                if (err_msg) |msg| {
                    log.err("{s}\n", .{std.mem.span(msg)});
                    llvm.LLVMDisposeMessage(msg);
                    return Error.CompilerFail;
                }
            }

            if (self.opt.run_jit) {
                r = try self.jit();
                s_run = false;
                self.sema.deinit();
            }

            c.deinit();
        }

        if (s_run) self.sema.deinit();

        try self.emitErrors();
        self.ast.deinit(self.allocator);

        return r;
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
                    log.debug("{d} | {s}", .{ l_count, l[0 .. e.token.col - 1] });
                    log.debug("{s}", .{l[e.token.col - 1 .. e.token.col + e.token.val.len - 1]});
                    log.debug("{s}\n", .{l[e.token.col + e.token.val.len - 1 ..]});
                    log.debug("    ", .{});
                    for (l[0 .. e.token.col - 1]) |_| {
                        log.debug(" ", .{});
                    }
                    for (l[e.token.col - 1 .. e.token.col + e.token.val.len - 1]) |_| {
                        log.debug("^", .{});
                    }
                    switch (e.severity) {
                        err.Severity.Error => {
                            log.debug(" \x1b[31m{s}\x1b[0m\n\n", .{e.msg});
                        },
                        err.Severity.Warn => {
                            log.debug(" \x1b[33m{s}\x1b[0m\n\n", .{e.msg});
                        },
                        err.Severity.Info => {
                            log.debug(" \x1b[36m{s}\x1b[0m\n\n", .{e.msg});
                        },
                    }
                } else {
                    log.debug("{d} | {s}\n", .{ l_count, l });
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
