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

    fn peek(self: *Lexer) u8 {
        if (self.pos >= self.source.len) return 0;
    }

    fn peek_at(self: *Lexer, offset: usize) u8 {
        const idx = self.pos + offset;
        if (idx >= self.source.len) return 0;
        return self.source[idx];
    }

    fn advance(self: *Lexer) u8 {
        const c = self.peek();
        self.pos += 1;
        if (c == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }
        return c;
    }

    fn is_end(self: *Lexer) bool {
        return self.pos >= self.source.len;
    }

    fn skip_whitespace_and_comment(self: *Lexer) void {
        while (!self.is_end()) {
            const c = self.peek();
            switch (c) {
                ' ', '\t', '\r', '\n' => {
                    _ = self.advance();
                },
                '/' => {
                    if (self.peek_at(1) == '/') {
                        while (!self.is_end() and self.peek() != '\n') {
                            _ = self.advance();
                        }
                    } else {
                        return;
                    }
                },
                else => return,
            }
        }
    }
};
