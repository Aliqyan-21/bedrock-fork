const std = @import("std");
const llvm = @import("llvm");
const lexer = @import("lexer.zig");
const compiler = @import("compiler.zig");
const err = @import("error.zig");
const token = @import("token.zig");
const parser = @import("parser.zig");
const ast = @import("ast.zig");
const cli = @import("cli.zig");

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.Args.iterate(init.minimal.args);
    defer args.deinit();

    const options = try cli.parse(&args);

    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, options.file, allocator, .limited(1 << 22));
    defer allocator.free(source);

    var c = compiler.Compiler.init(allocator, source, options);
    try c.run();
    // try c.emitErrors();
    defer c.deinit();

    var tokens = try lexer.tokenize(allocator, source);
    defer tokens.deinit(allocator);

    std.debug.print("\nTokens:\n", .{});
    for (tokens.items) |tok| {
        std.debug.print("{d}:{d:<3} {s:<12} '{s}'\n", .{ tok.line, tok.col, @tagName(tok.type), tok.val });
    }
}
