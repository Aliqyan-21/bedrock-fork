const std = @import("std");
const token = @import("token.zig");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");
const err = @import("error.zig");
const compiler = @import("compiler.zig");

pub const Parser = struct {
    allocator: std.mem.Allocator,
    lexer: lexer.Lexer,
    source: []const u8,
    compiler: *compiler.Compiler,

    pub fn init(allocator: std.mem.Allocator, source: []const u8, c: *compiler.Compiler) Parser {
        return Parser{
            .allocator = allocator,
            .lexer = lexer.Lexer.init(source),
            .source = source,
            .compiler = c,
        };
    }

    pub fn parse(self: *Parser) !ast.AST {
        var ast_res = ast.AST.init();
        ast_res.program = try self.parse_program();
        return ast_res;
    }

    pub fn parse_program(self: *Parser) !ast.Program {
        var program = ast.Program{ .items = undefined };
        program.items = try self.parse_items();
        return program;
    }

    pub fn parse_items(self: *Parser) !std.ArrayList(ast.Item) {
        // TODO: replace the [] fields with arrayList
        var items: std.ArrayList(ast.Item) = .empty;
        while (!self.lexer.is_end()) {
            var tok = try self.lexer.peek_token();
            if (tok.type == token.TokenType.eof) break;

            var is_pub = false;
            var is_inline = false;

            if (tok.type == token.TokenType.kw_pub) {
                _ = try self.lexer.next();
                is_pub = true;
                tok = try self.lexer.peek_token();
            }
            if (tok.type == token.TokenType.kw_inline) {
                _ = try self.lexer.next();
                is_inline = true;
                tok = try self.lexer.peek_token();
            }

            switch (tok.type) {
                .kw_import => {
                    const import_def = try self.parse_import_def();
                    try items.append(self.allocator, ast.Item{ .import_def = import_def });
                },
                .kw_func => {
                    const func_def = try self.parse_func_def(is_pub, is_inline);
                    try items.append(self.allocator, ast.Item{ .function = func_def });
                },
                .kw_proc => {
                    //todo: implement parse_proc_def
                },
                .kw_type => {
                    //todo: error if is_inline set (struct/enum defs take no "inline")
                    //todo:implement parse_type_item
                },
                .kw_extern => {
                    //todo: error if is_pub or is_inline set (extern takes no modifiers)
                    //todo: parse_extern_def();
                },
                .kw_var => {
                    //todo: error if inline set
                    //todo: implement parse_var_def
                },
                .kw_const => {
                    //todo: error if inline set
                    //todo: implement parse_const_def
                },
                else => {
                    // TODO:: error handling
                    _ = try self.lexer.next();
                    break;
                },
            }
        }
        return items;
    }

    pub fn parse_func_def(self: *Parser, is_pub: bool, is_inline: bool) !ast.FunctionDef {
        const func_tok = try self.lexer.next();
        var func_def = ast.FunctionDef{
            .is_pub = is_pub,
            .is_inline = is_inline,
            .name = "",
            .type_params = .empty,
            .params = undefined,
            .result = undefined,
            .body = undefined,
            .token = func_tok,
        };

        // todo: parse_type_params for the .type_params

        // get the function name
        const name_tok = try self.lexer.next();
        if (name_tok.type != token.TokenType.ident) {
            // TODO: add error handling
        }
        func_def.name = name_tok.val;

        // extect '('
        const lparen_tok = try self.lexer.next();
        if (lparen_tok.type != token.TokenType.l_paren) {
            // TODO: add error handling
        }

        // TODO: type params
        // parse parameters
        func_def.params = try self.parse_params();

        // expect '->'
        const arrow = try self.lexer.next();
        if (arrow.type != token.TokenType.arrow) {
            // TODO: add error handling
        }

        func_def.result = try self.parse_result();

        // parse block statement
        func_def.body = try self.parse_statement();

        return func_def;
    }

    pub fn parse_params(self: *Parser) !std.ArrayList(ast.Param) {
        var params: std.ArrayList(ast.Param) = .empty;

        while (true) {
            try params.append(
                self.allocator,
                try self.parse_param(),
            );

            const tok = try self.lexer.next();

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

    pub fn parse_param(self: *Parser) !ast.Param {
        var param = ast.Param{
            .name = "",
            .is_const = false,
            .type = undefined,
            .token = undefined,
        };

        // name
        var tok = try self.lexer.next();
        if (tok.type != token.TokenType.ident) {
            // error
        }
        param.token = tok;

        // :
        tok = try self.lexer.next();
        if (tok.type != token.TokenType.colon) {
            // error
        }

        // type
        param.type = try self.parse_type();

        return param;
    }

    pub fn parse_statement(self: *Parser) !std.ArrayList(ast.Stmt) {
        _ = self;
        var stmt: std.ArrayList(ast.Stmt) = .empty;
        _ = &stmt;
        return stmt;
    }

    pub fn parse_type(self: *Parser) !*ast.Type {
        const start_tok = try self.lexer.peek_token();

        var is_optional = false;
        if (start_tok.type == token.TokenType.optional) {
            _ = try self.lexer.next();
            is_optional = true;
        }

        // todo: implement parse_base_type

        var is_error_union = false;
        const is_it_bang = try self.lexer.peek_token();
        if (is_it_bang.type == token.TokenType.bang) {
            _ = try self.lexer.next();
            is_error_union = true;
        }

        const ty = try self.allocator.create(ast.Type);
        ty.* = .{
            .is_optional = is_optional,
            .is_error_union = is_error_union,
            .base = undefined,
            .token = start_tok,
        };
        return ty;
    }

    fn parse_base_type(self: *Parser) !ast.BaseType {
        const tok = try self.lexer.next();

        switch (tok.type) {
            .star => {
                const pointee = try self.parse_type();
                return ast.BaseType{ .pointer = pointee };
            },
            .l_bracket => return try self.parse_array_type(tok),
            .kw_func => return try self.parse_func_type(tok),
            .ident => {
                if (std.meta.stringToEnum(ast.PrimitiveType, tok.val)) |prim| {
                    return ast.BaseType{ .primitive = prim };
                }
                return ast.BaseType{ .named = try self.parse_named_type(tok) };
            },
            else => {
                return ast.BaseType{ .named = .{ .name = tok.val, .args = &[_]*ast.Type{}, .token = tok } };
            },
        }
    }

    fn parse_array_type() !ast.BaseType {
        //todo: implement
    }

    fn parse_func_type() !ast.BaseType {
        //todo: implement
    }

    fn parse_named_type() !ast.BaseType {
        //todo: implement
    }

    pub fn parse_result(self: *Parser) !*ast.Type {
        return self.parse_type();
    }

    pub fn parse_import_def(self: *Parser) !ast.ImportDef {
        var tok = try self.lexer.next();
        var import_def = ast.ImportDef{ .path = .empty, .token = tok };
        var count: usize = 0;
        while (tok.type != token.TokenType.semicolon) {
            count += 1;
            if (count == 10) break;
            // expect an ident
            tok = try self.lexer.next();
            if (tok.type != token.TokenType.ident) {
                try self.compiler.addError("expected ident ", err.Severity.Error, tok);
            }

            try import_def.path.append(self.allocator, tok.val);
            // can be a '.'
            tok = try self.lexer.next();
            if (tok.type != token.TokenType.semicolon) {
                if (tok.type != token.TokenType.dot) {
                    try self.compiler.addError("expected . or ; ", err.Severity.Error, tok);
                }
            }
        }
        return import_def;
    }
};
