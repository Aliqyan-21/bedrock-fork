const std = @import("std");
const testing = std.testing;
const bedrock = @import("bedrock");
const token = bedrock.token;
const lexer = bedrock.lexer;
const ast = bedrock.ast;

test "func_type ast print" {
    // func(i32, i32) -> i32
    var ty = ast.Type{ .primitive = .i32 };
    var params: [2]*ast.Type = .{ &ty, &ty };
    const result = ast.Result{ .plain = &ty };
    var func_type = ast.FuncType{
        .params = params[0..],
        .result = result,
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
