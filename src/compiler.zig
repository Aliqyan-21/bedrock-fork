const std = @import("std");
const llvm = @import("llvm");
const lexer = @import("lexer.zig");
const err = @import("error.zig");
const token = @import("token.zig");

pub const Compiler = struct {
    allocator: std.mem.Allocator,
    errors: std.ArrayList(err.SourceError),
    source: []const u8,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Compiler {
        return Compiler{
            .allocator = allocator,
            .errors = .empty,
            .source = source,
        };
    }

    pub fn run(self: *Compiler) !void {
        _ = self;
    }

    pub fn addError(self: *Compiler, msg: []const u8, severity: err.Severity, tok: token.Token) !void {
        try self.errors.append(self.allocator, err.SourceError{
            .msg = msg,
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
                    std.debug.print(" \x1b[31m{s}\x1b[0m\n\n", .{e.msg});
                } else {
                    std.debug.print("{d} | {s}\n", .{ l_count, l });
                }
                l_count += 1;
            }
        }
    }

    pub fn deinit(self: *Compiler) void {
        self.errors.deinit(self.allocator);
    }
};
