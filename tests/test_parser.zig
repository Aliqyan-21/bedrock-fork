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

fn parse_expression(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    var c = compiler.Compiler.init(allocator, source);
    var p = parser.Parser.init(allocator, source, &c);
    var expr = try p.parse_expression();
    const buf = try expr.parse_to_string(allocator);
    expr.deinit(allocator);
    c.deinit();
    return buf;
}

test "primitive type" {
    const res = try parse_type(std.testing.allocator, "i8");
    defer res.deinit(std.testing.allocator);
    try std.testing.expect(res.ty.base == .primitive);
    try std.testing.expectEqual(ast.PrimitiveType.i8, res.ty.base.primitive);
}

test "pointer type" {
    const res = try parse_type(std.testing.allocator, "*i32");
    defer res.deinit(std.testing.allocator);
    try std.testing.expect(res.ty.base == .pointer);
    try std.testing.expect(res.ty.base.pointer.base == .primitive);
    try std.testing.expectEqual(ast.PrimitiveType.i32, res.ty.base.pointer.base.primitive);
}

test "array type" {
    const res = try parse_type(std.testing.allocator, "[10]i32");
    defer res.deinit(std.testing.allocator);
    try std.testing.expect(res.ty.base == .array);
    try std.testing.expect(res.ty.base.array.size == .fixed);
    try std.testing.expectEqualStrings("10", res.ty.base.array.size.fixed);
    try std.testing.expectEqual(ast.PrimitiveType.i32, res.ty.base.array.elem.base.primitive);
}

test "optional and error-union modifiers" {
    const res = try parse_type(std.testing.allocator, "?i32!");
    defer res.deinit(std.testing.allocator);
    try std.testing.expect(res.ty.is_optional);
    try std.testing.expect(res.ty.is_error_union);
    try std.testing.expectEqual(ast.PrimitiveType.i32, res.ty.base.primitive);
}

test "named type with no args" {
    const res = try parse_type(std.testing.allocator, "Foo");
    defer res.deinit(std.testing.allocator);

    try std.testing.expect(res.ty.base == .named);
    try std.testing.expectEqualStrings("Foo", res.ty.base.named.name);
    try std.testing.expectEqual(@as(usize, 0), res.ty.base.named.args.len);
}

test "func type" {
    const res = try parse_type(std.testing.allocator, "func(i32, i32) -> i32");
    defer res.deinit(std.testing.allocator);
    try std.testing.expect(res.ty.base == .func);
    try std.testing.expectEqual(@as(usize, 2), res.ty.base.func.params.items.len);
    try std.testing.expectEqual(ast.PrimitiveType.i32, res.ty.base.func.result.base.primitive);
}

test "proc type" {
    const res = try parse_type(std.testing.allocator, "proc(i32)");
    defer res.deinit(std.testing.allocator);
    try std.testing.expect(res.ty.base == .proc);
    try std.testing.expectEqual(@as(usize, 1), res.ty.base.proc.params.items.len);
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
}

test "expression precedence parsing" {
    const allocator = std.testing.allocator;
    var buf = try parse_expression(std.testing.allocator, "10");
    try std.testing.expectEqualStrings(buf, "10");
    allocator.free(buf);
    buf = try parse_expression(std.testing.allocator, "10 + 10");
    try std.testing.expectEqualStrings(buf, "(10 + 10)");
    allocator.free(buf);
    buf = try parse_expression(std.testing.allocator, "10 + 10 * 10");
    try std.testing.expectEqualStrings(buf, "(10 + (10 * 10))");
    allocator.free(buf);
    buf = try parse_expression(std.testing.allocator, "10 + 10 * 10 - 10");
    try std.testing.expectEqualStrings(buf, "((10 + (10 * 10)) - 10)");
    allocator.free(buf);
    buf = try parse_expression(std.testing.allocator, "100 / 10 - 10");
    try std.testing.expectEqualStrings(buf, "((100 / 10) - 10)");
    allocator.free(buf);
}
