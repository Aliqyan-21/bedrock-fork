const std = @import("std");
const t = @import("token.zig");

pub const Lexer = struct {
    source: []const u8,
    pos: usize = 0,
    line: usize = 1,
    col: usize = 1,

    pub fn init(source: []const u8) Lexer {
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

    pub fn is_end(self: *Lexer) bool {
        return self.pos >= self.source.len;
    }

    fn skip_whitespace(self: *Lexer) void {
        while (!self.is_end()) {
            const c = self.peek();
            switch (c) {
                ' ', '\t', '\r', '\n' => {
                    _ = self.advance();
                },
                else => return,
            }
        }
    }

    fn is_comment(a: u8, b: u8) bool {
        return a == '/' and b == '/';
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

    pub fn scan(self: *Lexer, bump: bool) !t.Token {
        self.skip_whitespace();
        const line = self.line;
        const col = self.col;
        const pos = self.pos;

        defer {
            if (!bump) {
                self.line = line;
                self.col = col;
                self.pos = pos;
            }
        }

        if (self.is_end()) {
            return .{ .type = .eof, .val = "", .line = line, .col = col };
        }

        const c = self.peek();
        if (is_comment(c, self.peek_at(1))) {
            return self.read_comment(line, col);
        } else if (is_identifier(c)) {
            return self.read_identifier_or_keyword(line, col);
        } else if (is_digit(c)) {
            return try self.read_number(line, col);
        } else if (c == '"') {
            return try self.read_string(line, col);
        } else if (c == '\'') {
            return try self.read_char(line, col);
        } else {
            return try self.read_operator(line, col);
        }
    }

    pub fn peek_token(self: *Lexer) !t.Token {
        var tok: t.Token = undefined;
        while (true) {
            tok = try self.scan(false);
            if (tok.type == .comment)
                _ = try self.scan(true);
            if (tok.type != .comment) break;
        }
        return tok;
    }

    pub fn next(self: *Lexer) !t.Token {
        var tok: t.Token = undefined;
        while (true) {
            tok = try self.scan(true);
            if (tok.type != .comment) break;
        }
        return tok;
    }

    fn read_comment(self: *Lexer, line: usize, col: usize) t.Token {
        const start = self.pos;
        while (!self.is_end() and self.peek() != '\n') {
            _ = self.advance();
        }
        const text = self.source[start..self.pos];
        return .{ .type = .comment, .val = text, .line = line, .col = col };
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

    fn read_char(self: *Lexer, line: usize, col: usize) !t.Token {
        const start = self.pos;
        _ = self.advance();

        if (self.is_end() or self.peek() == '\n') return error.UnterminatedChar;

        if (self.peek() == '\\') {
            _ = self.advance();
            const e = self.peek();
            switch (e) {
                '\\', '\'', 'n', 't', 'r', '0' => _ = self.advance(),
                else => return error.InvalidEscape,
            }
        } else if (self.peek() == '\'') {
            return error.UnexpectedChar;
        } else {
            _ = self.advance();
        }

        if (self.is_end() or self.peek() != '\'') return error.UnterminatedChar;
        _ = self.advance();

        return self.make(.char, start, line, col);
    }

    fn read_string(self: *Lexer, line: usize, col: usize) !t.Token {
        const start = self.pos;
        _ = self.advance();

        while (true) {
            if (self.is_end()) return error.UnterminatedString;
            const c = self.peek();
            if (c == '"') {
                _ = self.advance();
                break;
            }
            if (c == '\n') return error.UnterminatedString;
            if (c == '\\') {
                _ = self.advance();
                const e = self.peek();
                switch (e) {
                    '\\', '"', 'n', 't', 'r', '0' => _ = self.advance(),
                    else => return error.InvalidEscape,
                }
                continue;
            }
            _ = self.advance();
        }

        return self.make(.string, start, line, col);
    }

    fn read_number(self: *Lexer, line: usize, col: usize) !t.Token {
        const start = self.pos;

        if (self.peek() == '0' and (self.peek_at(1) == 'x' or self.peek_at(1) == 'X')) {
            _ = self.advance();
            _ = self.advance();
            if (!is_hex_digit(self.peek()) and self.peek() != '_') {
                return error.UnexpectedChar;
            }
            while (!self.is_end() and (is_hex_digit(self.peek()) or self.peek() == '_')) {
                _ = self.advance();
            }
            return self.make(.integer, start, line, col);
        } else if (self.peek() == '0' and (self.peek_at(1) == 'o' or self.peek_at(1) == 'O')) {
            _ = self.advance();
            _ = self.advance();
            if (!is_oct_digit(self.peek()) and self.peek() != '_') {
                return error.UnexpectedChar;
            }
            while (!self.is_end() and (is_oct_digit(self.peek()) or self.peek() == '_')) {
                _ = self.advance();
            }
            return self.make(.integer, start, line, col);
        } else if (self.peek() == '0' and (self.peek_at(1) == 'b' or self.peek_at(1) == 'B')) {
            _ = self.advance();
            _ = self.advance();
            if (!is_bin_digit(self.peek()) and self.peek() != '_') {
                return error.UnexpectedChar;
            }
            while (!self.is_end() and (is_bin_digit(self.peek()) or self.peek() == '_')) {
                _ = self.advance();
            }
            return self.make(.integer, start, line, col);
        }

        // decimal
        while (!self.is_end() and (is_digit(self.peek()) or self.peek() == '_')) {
            _ = self.advance();
        }

        // float
        if (self.peek() == '.' and self.peek_at(1) != '.' and is_digit(self.peek_at(1))) {
            _ = self.advance();
            while (!self.is_end() and (is_digit(self.peek()) or self.peek() == '_')) {
                _ = self.advance();
            }
            return self.make(.float, start, line, col);
        }

        return self.make(.integer, start, line, col);
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
                    if (self.peek() == '.') {
                        _ = self.advance();
                        return self.make(.dot_dot_dot, start, line, col);
                    }
                    if (self.peek() == '=') {
                        _ = self.advance();
                        return self.make(.dot_dot_eq, start, line, col);
                    }
                    return self.make(.dot_dot, start, line, col);
                }
                return self.make(.dot, start, line, col);
            },
            '~' => return self.make(.tilde, start, line, col),
            '?' => return self.make(.optional, start, line, col),
            '(' => return self.make(.l_paren, start, line, col),
            ')' => return self.make(.r_paren, start, line, col),
            '[' => return self.make(.l_bracket, start, line, col),
            ']' => return self.make(.r_bracket, start, line, col),
            ',' => return self.make(.comma, start, line, col),
            ':' => return self.make(.colon, start, line, col),
            ';' => return self.make(.semicolon, start, line, col),
            else => return error.Unknown,
        }
    }

    fn make(self: *Lexer, tt: t.TokenType, start: usize, line: usize, col: usize) t.Token {
        return .{ .type = tt, .val = self.source[start..self.pos], .line = line, .col = col };
    }
};

// convenience function
pub fn tokenize(allocator: std.mem.Allocator, source: []const u8) !std.ArrayList(t.Token) {
    var lexer = Lexer.init(source);
    var tokens: std.ArrayList(t.Token) = .empty;
    errdefer tokens.deinit(allocator);
    while (true) {
        const tok = try lexer.next();
        try tokens.append(allocator, tok);
        if (tok.type == .eof) break;
    }
    return tokens;
}
