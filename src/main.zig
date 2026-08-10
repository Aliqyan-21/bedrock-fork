const std = @import("std");
const llvm = @import("llvm");
const l = @import("lexer.zig");
const t = @import("token.zig");

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

    var lexer = l.Lexer.init(source);
    var tokens: std.ArrayList(t.Token) = .empty;
    defer tokens.deinit(allocator);

    while (true) {
        const tok = try lexer.next();
        try tokens.append(allocator, tok);
        if (tok.type == .eof) break;
    }

    for (tokens.items) |tok| {
        std.debug.print("{d}:{d:<3} {s:<12} '{s}'\n", .{ tok.line, tok.col, @tagName(tok.type), tok.val });
    }
}
