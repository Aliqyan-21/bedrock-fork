const std = @import("std");
const llvm = @import("llvm");
const lexer = @import("lexer.zig");
const compiler = @import("compiler.zig");
const err = @import("error.zig");
const token = @import("token.zig");
const parser = @import("parser.zig");
const ast = @import("ast.zig");

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.Args.iterate(init.minimal.args);
    defer args.deinit();
    _ = args.next();

    var file_name: []const u8 = "";
    if (args.next()) |f| {
        file_name = f;
    } else {
        @panic("not receive any file name");
    }

    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, file_name, allocator, .limited(1 << 22));
    defer allocator.free(source);

    var p = parser.Parser.init(allocator, source);
    var p_res = try p.parse();
    try p_res.print();
    p_res.deinit(allocator);

    var tokens = try lexer.tokenize(allocator, source);
    defer tokens.deinit(allocator);

    std.debug.print("\nTokens:\n", .{});
    for (tokens.items) |tok| {
        std.debug.print("{d}:{d:<3} {s:<12} '{s}'\n", .{ tok.line, tok.col, @tagName(tok.type), tok.val });
    }
}
