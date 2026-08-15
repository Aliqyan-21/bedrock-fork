const std = @import("std");
const token = @import("token.zig");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");
const err = @import("error.zig");

pub const Parser = struct {
    allocator: std.mem.Allocator,
    lexer: lexer.Lexer,
    source: []const u8,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Parser {
        return Parser{
            .allocator = allocator,
            .lexer = lexer.Lexer.init(source),
            .source = source,
        };
    }

    pub fn parse(self: *Parser) !ast.AST {
        var ast_res = ast.AST.init();
        ast_res.program = try self.parseProgram();
        return ast_res;
    }

    pub fn parseProgram(self: *Parser) !ast.Program {
        var program = ast.Program{ .items = undefined };
        program.items = try self.parseItems();
        return program;
    }

    pub fn parseItems(self: *Parser) !std.ArrayList(ast.Item) {
        // TODO: replace the [] fields with arrayList
        var items: std.ArrayList(ast.Item) = .empty;
        var count: usize = 0;
        while (!self.lexer.is_end()) {
            const tok = try self.lexer.next(true);
            // TODO: check for pub and inline keyword
            switch (tok.type) {
                token.TokenType.kw_func => {
                    const func_def = try self.parseFuncDef();
                    try items.append(self.allocator, ast.Item{ .function = func_def });
                },
                else => {
                    // TODO:
                    break;
                },
            }
            count += 1;
        }
        return items;
    }

    pub fn parseFuncDef(self: *Parser) !ast.FunctionDef {
        var func_def = ast.FunctionDef{
            .is_pub = false,
            .is_inline = false,
            .name = "",
            .type_params = .empty,
            .params = undefined,
            .result = undefined,
            .body = undefined,
            .token = undefined,
        };

        // get the function name
        const name_tok = try self.lexer.next(true);
        if (name_tok.type != token.TokenType.ident) {
            // TODO: add error handling
        }
        func_def.name = name_tok.val;

        // extect '('
        const lparen_tok = try self.lexer.next(true);
        if (lparen_tok.type != token.TokenType.l_paren) {
            // TODO: add error handling
        }

        // TODO: type params
        // parse parameters
        func_def.params = try self.parseParams();

        // expect '->'
        const arrow = try self.lexer.next(true);
        if (arrow.type != token.TokenType.arrow) {
            // TODO: add error handling
        }

        func_def.result = try self.parseResult();

        // parse block statement
        func_def.body = try self.parseStatement();

        return func_def;
    }

    pub fn parseParams(self: *Parser) !std.ArrayList(ast.Param) {
        var params: std.ArrayList(ast.Param) = .empty;

        while (true) {
            try params.append(
                self.allocator,
                try self.parseParam(),
            );

            const tok = try self.lexer.next(true);

            switch (tok.type) {
                .r_paren => break,
                .comma => continue,
                else => {
                    // error: expected ',' or ')'
                },
            }
        }

        return params;
    }

    pub fn parseParam(self: *Parser) !ast.Param {
        var param = ast.Param{
            .name = "",
            .is_optional = false,
            .is_const = false,
            .type = undefined,
            .token = undefined,
        };

        // name
        var tok = try self.lexer.next(true);
        if (tok.type != token.TokenType.ident) {
            // error
        }
        param.name = tok.val;

        // :
        tok = try self.lexer.next(true);
        if (tok.type != token.TokenType.colon) {
            // error
        }

        // type
        tok = try self.lexer.next(true);
        param.type = try self.parseType(tok.val);

        return param;
    }

    pub fn parseStatement(self: *Parser) !std.ArrayList(ast.Stmt) {
        _ = self;
        var stmt: std.ArrayList(ast.Stmt) = .empty;
        _ = &stmt;
        return stmt;
    }

    pub fn parseType(self: *Parser, tok_val: []const u8) !*ast.Type {
        const ty = try self.allocator.create(ast.Type);
        if (std.mem.eql(u8, tok_val, "i32")) {
            ty.* = .{ .primitive = .i32 };
        } else {
            // TODO
        }
        return ty;
    }

    pub fn parseResult(self: *Parser) !ast.Result {
        const tok = try self.lexer.next(true);
        var result: ast.Result = undefined;
        if (std.mem.eql(u8, tok.val, "i32")) {
            const ty = try self.allocator.create(ast.Type);
            ty.* = .{ .primitive = .i32 };
            result = .{ .plain = ty };
        }
        return result;
    }
};
