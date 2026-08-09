const std = @import("std");
const llvm = @import("llvm");
const l = @import("lexer.zig");
const t = @import("token.zig");

pub fn main() !void {
    const source =
        \\pub proc main()
        \\  io.println("Hello, World");
        \\end
        \\
    ;

    _ = l.Lexer.init(source);
}
