const std = @import("std");
const bedrock = @import("bedrock");
const ast = bedrock.ast;
const compiler = bedrock.compiler;
const parser = bedrock.parser;

const TypeResult = struct {
    ty: *ast.Type,
    c: *compiler.Compiler,
    fn deinit(self: TypeResult, allocator: std.mem.Allocator) void {
        self.ty.deinit(allocator);
        allocator.destroy(self.ty);
        self.c.deinit();
        allocator.destroy(self.c);
    }
};

fn parse_type(allocator: std.mem.Allocator, source: []const u8) !TypeResult {
    const c = try allocator.create(compiler.Compiler);
    c.* = compiler.Compiler.init(allocator, source);
    var p = parser.Parser.init(allocator, source, c);
    const ty = try p.parse_type();
    return .{ .ty = ty, .c = c };
}

test "named type with no args" {
    const res = try parse_type(std.testing.allocator, "Foo");
    defer res.deinit(std.testing.allocator);

    try std.testing.expect(res.ty.base == .named);
    try std.testing.expectEqualStrings("Foo", res.ty.base.named.name);
    try std.testing.expectEqual(@as(usize, 0), res.ty.base.named.args.len);
}

test "named type with args" {
    const res = try parse_type(std.testing.allocator, "Map[str, List[Option[i32]]]");
    defer res.deinit(std.testing.allocator);

    try std.testing.expect(res.ty.base == .named);
    try std.testing.expectEqualStrings("Map", res.ty.base.named.name);
    try std.testing.expectEqual(@as(usize, 2), res.ty.base.named.args.len);
    try std.testing.expectEqual(ast.PrimitiveType.str, res.ty.base.named.args[0].base.primitive);

    const ls = res.ty.base.named.args[1];
    try std.testing.expect(ls.base == .named);
    try std.testing.expectEqualStrings("List", ls.base.named.name);
    try std.testing.expectEqual(@as(usize, 1), ls.base.named.args.len);
    // and so on...lazy
}
