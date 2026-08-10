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

fn expect_types(source: []const u8, expected: []const token.TokenType) !void {
    const got = try types(testing.allocator, source);
    defer testing.allocator.free(got);
    try testing.expectEqualSlices(token.TokenType, expected, got);
}

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
