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

    fn is_identifier(c: u8) bool {
        return (std.ascii.isAlphabetic(c) or c == '_');
    }

    fn is_ident_cont(c: u8) bool {
        return is_identifier(c) or (std.ascii.isDigit(c));
    }

    fn is_digit(c: u8) bool {
        return std.ascii.isDigit(c);
    }

    fn is_hex_digit(c: u8) bool {
        return is_digit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
    }

    fn is_oct_digit(c: u8) bool {
        return c >= '0' and c <= '7';
    }

    fn is_bin_digit(c: u8) bool {
        return c >= '0' and c <= '1';
    }

    pub fn next(self: *Lexer) !t.Token {
        self.skip_whitespace_and_comment();
        const line = self.line;
        const col = self.col;

        if (self.is_end()) {
            return .{ .kind = .eof, .val = "", .line = line, .col = col };
        }

        const c = self.peek();

        std.debug.print("{c}\n", c);
    }
};
