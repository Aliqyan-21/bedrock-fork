const std = @import("std");
const llvm = @import("llvm");
const lexer = @import("lexer.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\pub proc main()
        \\  io.println("Hello, World");
        \\end
        \\
    ;

    var tokens = try lexer.tokenize(allocator, source);
    defer tokens.deinit(allocator);

    for (tokens.items) |tok| {
        std.debug.print("{d}:{d:<3} {s:<12} '{s}'\n", .{ tok.line, tok.col, @tagName(tok.type), tok.val });
    }
}
