const std = @import("std");
const llvm = @import("llvm");
const lexer = @import("lexer.zig");
const err = @import("error.zig");
const token = @import("token.zig");
const parser = @import("parser.zig");
const ast = @import("ast.zig");
const codegen = @import("codegen.zig");

pub const Compiler = struct {
    allocator: std.mem.Allocator,
    errors: std.ArrayList(err.SourceError),
    source: []const u8,
    ast: ast.AST,
    mod: llvm.LLVMModuleRef,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Compiler {
        return Compiler{
            .allocator = allocator,
            .errors = .empty,
            .source = source,
            .ast = undefined,
            .mod = undefined,
        };
    }

    pub fn run(self: *Compiler) !void {
        var p = parser.Parser.init(self.allocator, self.source, self);
        self.ast = try p.parse();
        try self.ast.print();
        var c = codegen.Codegen.init(self.allocator, self);
        self.mod = try c.codegen();
        var error_message: [*c]u8 = null;
        const res = llvm.LLVMPrintModuleToFile(self.mod, "./corpus/codegen/dump.ll", &error_message);
        if (res != 0) {
            if (error_message) |msg| {
                std.debug.print("LLVM: {s}\n", .{std.mem.span(msg)});

                llvm.LLVMDisposeMessage(msg);
            }
        }
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
