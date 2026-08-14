const std = @import("std");
const llvm = @import("llvm");
const lexer = @import("lexer.zig");
const compiler = @import("compiler.zig");
const err = @import("error.zig");
const token = @import("token.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\import io
        \\// Main function
        \\func proc add(x i32, y: i32) -> i32
        \\  return x + y;
        \\end
        \\
    ;

    var c = compiler.Compiler.init(allocator, source);
    try c.run();
    defer c.deinit();
    const err_tok = token.Token{
        .type = token.TokenType.ident,
        .val = "i32",
        .line = 3,
        .col = 17,
    };
    try c.addError("expect : here got i32", err.Severity.Error, err_tok);
    try c.emitErrors();

    var tokens = try lexer.tokenize(allocator, source);
    defer tokens.deinit(allocator);

    std.debug.print("\nTokens:\n", .{});
    for (tokens.items) |tok| {
        std.debug.print("{d}:{d:<3} {s:<12} '{s}'\n", .{ tok.line, tok.col, @tagName(tok.type), tok.val });
    }
}
