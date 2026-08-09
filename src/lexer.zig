const std = @import("std");
const t = @import("token.zig");

pub const Lexer = struct {
    source: []const u8,
    pos: usize = 0,
    line: usize = 1,
    col: usize = 1,

    pub fn init(source: []const u8) Lexer {
        std.debug.print("{s}\n", .{source});
        return .{ .source = source };
    }
};
