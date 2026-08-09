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
        return self.source[self.pos];
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
            self.col = 1;
        } else {
            self.col += 1;
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
            return .{ .type = .eof, .val = "", .line = line, .col = col };
        }

        const c = self.peek();

        std.debug.print("{c}\n", .{c});

        if (is_identifier(c)) {
            return self.read_identifier_or_keyword(line, col);
        }
        if (is_digit(c)) {
            // todo: read number
        }
        if (c == '"') {
            // todo: read string
        }
        if (c == '\'') {
            // todo: read char
        }

        return self.read_operator(line, col);
    }

    fn read_identifier_or_keyword(self: *Lexer, line: usize, col: usize) t.Token {
        const start = self.pos;
        while (!self.is_end() and is_ident_cont(self.peek())) {
            _ = self.advance();
        }
        const text = self.source[start..self.pos];
        const kind = t.lookup_keyword(text) orelse .ident;
        return .{ .type = kind, .val = text, .line = line, .col = col };
    }

    fn read_operator(self: *Lexer, line: usize, col: usize) !t.Token {
        const start = self.pos;
        const c = self.advance();

        switch (c) {
            '-' => {
                if (self.peek() == '>') {
                    _ = self.advance();
                    return self.make(.arrow, start, line, col);
                }
                if (self.peek() == '=') {
                    _ = self.advance();
                    return self.make(.minus_eq, start, line, col);
                }
                return self.make(.minus, start, line, col);
            },
            '=' => {
                if (self.peek() == '=') {
                    _ = self.advance();
                    return self.make(.eq_eq, start, line, col);
                }
                return self.make(.eq, start, line, col);
            },
            '!' => {
                if (self.peek() == '=') {
                    _ = self.advance();
                    return self.make(.bang_eq, start, line, col);
                }
                return self.make(.bang, start, line, col);
            },
            '<' => {
                if (self.peek() == '<') {
                    _ = self.advance();
                    if (self.peek() == '=') {
                        _ = self.advance();
                        return self.make(.shl_eq, start, line, col);
                    }
                    return self.make(.shl, start, line, col);
                }
                if (self.peek() == '=') {
                    _ = self.advance();
                    return self.make(.lt_eq, start, line, col);
                }
                return self.make(.lt, start, line, col);
            },
            '>' => {
                if (self.peek() == '>') {
                    _ = self.advance();
                    if (self.peek() == '=') {
                        _ = self.advance();
                        return self.make(.shr_eq, start, line, col);
                    }
                    return self.make(.shr, start, line, col);
                }
                if (self.peek() == '=') {
                    _ = self.advance();
                    return self.make(.gt_eq, start, line, col);
                }
                return self.make(.gt, start, line, col);
            },
            '&' => {
                if (self.peek() == '&') {
                    _ = self.advance();
                    return self.make(.amp_amp, start, line, col);
                }
                if (self.peek() == '=') {
                    _ = self.advance();
                    return self.make(.amp_eq, start, line, col);
                }
                return self.make(.amp, start, line, col);
            },
            '|' => {
                if (self.peek() == '|') {
                    _ = self.advance();
                    return self.make(.pipe_pipe, start, line, col);
                }
                if (self.peek() == '=') {
                    _ = self.advance();
                    return self.make(.pipe_eq, start, line, col);
                }
                return self.make(.pipe, start, line, col);
            },
            '+' => {
                if (self.peek() == '=') {
                    _ = self.advance();
                    return self.make(.plus_eq, start, line, col);
                }
                return self.make(.plus, start, line, col);
            },
            '*' => {
                if (self.peek() == '=') {
                    _ = self.advance();
                    return self.make(.star_eq, start, line, col);
                }
                return self.make(.star, start, line, col);
            },
            '/' => {
                if (self.peek() == '=') {
                    _ = self.advance();
                    return self.make(.slash_eq, start, line, col);
                }
                return self.make(.slash, start, line, col);
            },
            '%' => {
                if (self.peek() == '=') {
                    _ = self.advance();
                    return self.make(.percent_eq, start, line, col);
                }
                return self.make(.percent, start, line, col);
            },
            '^' => {
                if (self.peek() == '=') {
                    _ = self.advance();
                    return self.make(.caret_eq, start, line, col);
                }
                return self.make(.caret, start, line, col);
            },
            '.' => {
                if (self.peek() == '.') {
                    _ = self.advance();
                    return self.make(.dot_dot, start, line, col);
                }
                return self.make(.dot, start, line, col);
            },
            '~' => return self.make(.tilde, start, line, col),
            '?' => return self.make(.question, start, line, col),
            '(' => return self.make(.l_paren, start, line, col),
            ')' => return self.make(.r_paren, start, line, col),
            '[' => return self.make(.l_bracket, start, line, col),
            ']' => return self.make(.r_bracket, start, line, col),
            '{' => return self.make(.l_brace, start, line, col),
            '}' => return self.make(.r_brace, start, line, col),
            ',' => return self.make(.comma, start, line, col),
            ':' => return self.make(.colon, start, line, col),
            ';' => return self.make(.semicolon, start, line, col),
            else => return error.Unkown,
        }
    }

    fn make(self: *Lexer, tt: t.TokenType, start: usize, line: usize, col: usize) t.Token {
        return .{ .type = tt, .val = self.source[start..self.pos], .line = line, .col = col };
    }
};
