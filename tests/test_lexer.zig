const std = @import("std");
const testing = std.testing;
const bedrock = @import("bedrock");
const token = bedrock.token;
const lexer = bedrock.lexer;

fn types(allocator: std.mem.Allocator, source: []const u8) ![]token.TokenType {
    var tokens = try lexer.tokenize(allocator, source);
    defer tokens.deinit(allocator);

    var result = try allocator.alloc(token.TokenType, tokens.items.len - 1);
    for (tokens.items[0 .. tokens.items.len - 1], 0..) |tok, i| {
        result[i] = tok.type;
    }
    return result;
}

fn vals(allocator: std.mem.Allocator, source: []const u8) ![]const []const u8 {
    var tokens = try lexer.tokenize(allocator, source);
    defer tokens.deinit(allocator);

    var result = try allocator.alloc([]const u8, tokens.items.len - 1);
    for (tokens.items[0 .. tokens.items.len - 1], 0..) |tok, i| {
        result[i] = tok.val;
    }
    return result;
}

fn expect_types(source: []const u8, expected: []const token.TokenType) !void {
    const got = try types(testing.allocator, source);
    defer testing.allocator.free(got);
    try testing.expectEqualSlices(token.TokenType, expected, got);
}

fn expect_vals(source: []const u8, expected: []const []const u8) !void {
    const got = try vals(testing.allocator, source);
    defer testing.allocator.free(got);
    try testing.expectEqual(expected.len, got.len);
    for (expected, got) |exp, act| {
        try testing.expectEqualStrings(exp, act);
    }
}

// kws and idents

test "identifiers that start with kw are not kws" {
    try expect_types("structx", &.{.ident});
    try expect_types("forever", &.{.ident});
    try expect_types("interned", &.{.ident});
    try expect_types("endpoint", &.{.ident});
    try expect_types("publisher", &.{.ident});
}

test "identifiers with digit and underscores" {
    try expect_types("age2", &.{.ident});
    try expect_types("_temp", &.{.ident});
    try expect_types("player_1_score", &.{.ident});
}

// numbers

test "integers, with and without '_' separators" {
    try expect_types("0", &.{.integer});
    try expect_types("42", &.{.integer});
    try expect_types("1_000_000", &.{.integer});
}

test "hex, octal, and binary" {
    try expect_types("0xFF", &.{.integer});
    try expect_types("0xFF_00", &.{.integer});
    try expect_types("0o17", &.{.integer});
    try expect_types("0b1010", &.{.integer});
}

test "digit + dot with no following digit is int and dot, not a float" {
    try expect_types("3.", &.{ .integer, .dot });
}

test "range operator is not a float" {
    try expect_types("0..3", &.{ .integer, .dot_dot, .integer });
}

// string and char

test "string literal with escapes" {
    try expect_types("\"Hello, \\nEd!\"", &.{.string});
}

test "unterminated string is error" {
    try testing.expectError(error.UnterminatedString, lexer.tokenize(testing.allocator, "\"never closed"));
}

test "char, plain and escaped" {
    try expect_types("'A'", &.{.char});
    try expect_vals("'A'", &.{"'A'"});
    try expect_types("'\\n'", &.{.char});
}

test "empty char is error" {
    try testing.expectError(error.UnexpectedChar, lexer.tokenize(testing.allocator, "''"));
}

// operators

test "multi char operators win over single char" {
    try expect_types("->", &.{.arrow});
    try expect_types("==", &.{.eq_eq});
    try expect_types("!=", &.{.bang_eq});
    try expect_types("<=", &.{.lt_eq});
    try expect_types(">=", &.{.gt_eq});
    try expect_types("&&", &.{.amp_amp});
    try expect_types("||", &.{.pipe_pipe});
    try expect_types("<<", &.{.shl});
    try expect_types(">>", &.{.shr});
    try expect_types("<<=", &.{.shl_eq});
    try expect_types(">>=", &.{.shr_eq});
}

test "short assignment operator" {
    try expect_types("+=", &.{.plus_eq});
    try expect_types("-=", &.{.minus_eq});
    try expect_types("*=", &.{.star_eq});
    try expect_types("/=", &.{.slash_eq});
    try expect_types("%=", &.{.percent_eq});
    try expect_types("&=", &.{.amp_eq});
    try expect_types("|=", &.{.pipe_eq});
    try expect_types("^=", &.{.caret_eq});
}

test "single char" {
    try expect_types("- - -", &.{ .minus, .minus, .minus });
    try expect_types("< >", &.{ .lt, .gt });
    try expect_types("&", &.{.amp});
    try expect_types("|", &.{.pipe});
}

test "dot vs dot_dot" {
    try expect_types(".", &.{.dot});
    try expect_types("..", &.{.dot_dot});
    try expect_types("a.b", &.{ .ident, .dot, .ident });
}

// generrics

test "generic declaration brackets are plain bracker/comma/ident tokens" {
    try expect_types("Pair[T, U]", &.{ .ident, .l_bracket, .ident, .comma, .ident, .r_bracket });
}

// whitespace and comment

test "whitespace and newlines discarded" {
    var tokens = try lexer.tokenize(testing.allocator, "var\n           x");
    defer tokens.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), tokens.items[0].line);
    try testing.expectEqual(@as(usize, 2), tokens.items[1].line);
    try testing.expectEqual(@as(usize, 12), tokens.items[1].col);
}

// errors and eof

test "unrecognized char is error" {
    try testing.expectError(error.Unknown, lexer.tokenize(testing.allocator, "@"));
}

test "eof token is emitted exactly once at the of the stream" {
    var tokens = try lexer.tokenize(testing.allocator, "var x = 1;");
    defer tokens.deinit(testing.allocator);
    try testing.expectEqual(token.TokenType.eof, tokens.items[tokens.items.len - 1].type);
    var ct: usize = 0;
    for (tokens.items) |tok| {
        if (tok.type == .eof) ct += 1;
    }
    try testing.expectEqual(@as(usize, 1), ct);
}
