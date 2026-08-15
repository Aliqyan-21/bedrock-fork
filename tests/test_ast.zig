const std = @import("std");
const testing = std.testing;
const bedrock = @import("bedrock");
const token = bedrock.token;
const lexer = bedrock.lexer;
const ast = bedrock.ast;

test "func_type ast print" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    // func(i32, i32) -> i32
    var ty = ast.Type{
        .base = .{ .primitive = .i32 },
        .token = token.Token{
            .type = token.TokenType.ident,
            .val = "i32",
            .line = 1,
            .col = 1,
        },
    };
    var params: std.ArrayList(*ast.Type) = .empty;
    defer params.deinit(allocator);

    try params.append(allocator, &ty);
    try params.append(allocator, &ty);
    var func_type = ast.FuncType{
        .params = params,
        .result = &ty,
        .token = token.Token{
            .type = token.TokenType.kw_func,
            .val = "func",
            .line = 1,
            .col = 1,
        },
    };
    _ = &func_type;
    // try func_type.print(0);
    // std.testing.expectEqualStrings("func(i32, i32) -> i32", func_type.toString());
}
