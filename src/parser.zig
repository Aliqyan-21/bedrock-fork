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

    fn expect(self: *Parser, ty: token.TokenType, msg: []const u8) !?token.Token {
        const tok = try self.lexer.peek_token();
        if (tok.type != ty) {
            try self.compiler.addError(msg, err.Severity.Error, tok);
            return null;
        }
        return try self.lexer.next();
    }

    // when error occurs and when a production can't sensibly continue
    // (e.g. -> missing in a func type) then call this to reach a good
    // point where u can continue parsing.
    fn sync(self: *Parser, stop_set: []const token.TokenType) !void {
        var depth: usize = 0;
        while (true) {
            const t = try self.lexer.peek_token();
            if (t.type == .eof) return;
            if (depth == 0) {
                for (stop_set) |s| {
                    if (t.type == s) return; // not consume it, as code after this needs this token
                }
            }
            _ = try self.lexer.next();
            switch (t.type) {
                .l_paren, .l_bracket => depth += 1,
                .r_paren, .r_bracket => if (depth > 0) {
                    depth -= 1;
                },
                else => {},
            }
        }
    }

    // error type token
    fn error_type(self: *Parser, tok: token.Token) !*ast.Type {
        const ty = try self.allocator.create(ast.Type);
        ty.* = .{
            .is_optional = false,
            .is_error_union = false,
            .base = .{ .named = .{ .name = "<error>", .args = &[_]*ast.Type{}, .token = tok } },
            .token = tok,
        };
        return ty;
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
                    const proc_def = try self.parse_proc_def(is_pub, is_inline);
                    try items.append(self.allocator, ast.Item{ .proc = proc_def });
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
                    var const_def = try self.parse_const_def();
                    const_def.is_pub = is_pub;
                    const_def.is_global = true;
                    try items.append(self.allocator, ast.Item{ .const_def = const_def });
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
        const name_tok = try self.expect(.ident, "expected function name") orelse token.Token{ .type = .ident, .val = "", .line = func_tok.line, .col = func_tok.col };
        func_def.name = name_tok.val;

        // extect '('
        _ = try self.expect(.l_paren, "expected '('");

        // TODO: type params
        // parse parameters
        func_def.params = try self.parse_params();

        // expect '->'
        _ = try self.expect(.arrow, "expected '->'");

        func_def.result = try self.parse_result();

        // parse block statement
        func_def.body = try self.parse_statement();

        return func_def;
    }

    pub fn parse_proc_def(self: *Parser, is_pub: bool, is_inline: bool) !ast.ProcDef {
        const proc_tok = try self.lexer.next();
        var proc_def = ast.ProcDef{
            .is_pub = is_pub,
            .is_inline = is_inline,
            .name = "",
            .type_params = .empty,
            .params = .empty,
            .body = undefined,
            .token = proc_tok,
        };

        const tok = try self.expect(.ident, "expected proc name") orelse token.Token{ .type = .ident, .val = "<error>", .line = proc_tok.line, .col = proc_tok.col };
        proc_def.name = tok.val;

        //todo: parse_type_params

        if (try self.expect(.l_paren, "expected '('") == null) {
            try self.sync(&.{ .r_paren, .kw_end });
        } else {
            proc_def.params = try self.parse_params();
        }

        proc_def.body = try self.parse_statement();

        return proc_def;
    }

    pub fn parse_params(self: *Parser) !std.ArrayList(ast.Param) {
        var params: std.ArrayList(ast.Param) = .empty;

        const first = try self.lexer.peek_token();
        if (first.type == token.TokenType.r_paren) {
            _ = try self.lexer.next();
            return params;
        }

        while (true) {
            try params.append(self.allocator, try self.parse_param());
            const tok = try self.lexer.next();
            switch (tok.type) {
                .r_paren => break,
                .comma => {
                    const nxt = try self.lexer.peek_token();
                    if (nxt.type == token.TokenType.r_paren) {
                        _ = try self.lexer.next();
                        break;
                    }
                    continue;
                },
                else => {
                    try self.compiler.addError("expected ',' or ')'", err.Severity.Error, tok);

                    try self.sync(&.{ .comma, .r_paren });

                    const hmm = try self.lexer.peek_token();
                    if (hmm.type == .comma) {
                        _ = try self.lexer.next();
                        continue;
                    } else if (hmm.type == .r_paren) {
                        _ = try self.lexer.next();
                        break;
                    } else {
                        // can't recover
                        break;
                    }
                    break;
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
        _ = try self.expect(.ident, "expected identifier");

        // :
        _ = try self.expect(.colon, "expected ':'");

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

    pub fn parse_type(self: *Parser) anyerror!*ast.Type {
        const start_tok = try self.lexer.peek_token();

        var is_optional = false;
        if (start_tok.type == token.TokenType.optional) {
            _ = try self.lexer.next();
            is_optional = true;
        }

        const base = try self.parse_base_type();

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
            .base = base,
            .token = start_tok,
        };
        return ty;
    }

    fn parse_base_type(self: *Parser) anyerror!ast.BaseType {
        const tok = try self.lexer.next();

        switch (tok.type) {
            .star => {
                const pointee = try self.parse_type();
                return ast.BaseType{ .pointer = pointee };
            },
            .l_bracket => return try self.parse_array_type(tok),
            // fixme: uncomment this for impl
            .kw_func => return try self.parse_func_type(tok),
            .kw_proc => return try self.parse_proc_type(tok),
            .ident => {
                if (std.meta.stringToEnum(ast.PrimitiveType, tok.val)) |prim| {
                    return ast.BaseType{ .primitive = prim };
                }
                // fixme: uncomment this for impl:
                // return ast.BaseType{ .named = try self.parse_named_type(tok) };
                // delet this:
                return ast.BaseType{ .named = .{ .name = tok.val, .args = &[_]*ast.Type{}, .token = tok } };
            },
            else => {
                try self.compiler.addError("expected a type", err.Severity.Error, tok);
                return ast.BaseType{ .named = .{ .name = tok.val, .args = &[_]*ast.Type{}, .token = tok } };
            },
        }
    }

    fn parse_array_type(self: *Parser, tok: token.Token) !ast.BaseType {
        const size_tok = try self.lexer.peek_token();
        var size: ast.ArraySize = .inferred;

        if (size_tok.type == token.TokenType.integer) {
            _ = try self.lexer.next();
            size = .{ .fixed = size_tok.val };
        } else if (size_tok.type == token.TokenType.ident and std.mem.eql(u8, size_tok.val, "_")) {
            size = .inferred;
        } else {
            try self.compiler.addError("expected an INTEGER or '_'", err.Severity.Error, size_tok);
        }

        if (try self.expect(.r_bracket, "expected ']'") == null) {
            try self.sync(&.{ .comma, .r_paren });
            return ast.BaseType{ .array = .{ .size = size, .elem = try self.error_type(tok), .token = tok } };
        }

        const elem = try self.parse_type();

        return ast.BaseType{ .array = ast.ArrayType{ .size = size, .elem = elem, .token = tok } };
    }

    fn parse_func_type(self: *Parser, tok: token.Token) !ast.BaseType {
        _ = try self.expect(.l_paren, "expected '('");

        const params = try self.parse_type_list();

        if (try self.expect(.arrow, "expected '->'") == null) {
            try self.sync(&.{ .r_paren, .comma });
            return ast.BaseType{ .func = .{ .params = params, .result = try self.error_type(tok), .token = tok } };
        }
        const result = try self.parse_type();

        return ast.BaseType{ .func = ast.FuncType{ .params = params, .result = result, .token = tok } };
    }

    fn parse_proc_type(self: *Parser, tok: token.Token) !ast.BaseType {
        if (try self.expect(.l_paren, "expected '('") == null) {
            try self.sync(&.{ .r_paren, .comma });
            return ast.BaseType{ .proc = ast.ProcType{ .params = .empty, .token = tok } };
        }
        const params = try self.parse_type_list();
        return ast.BaseType{ .proc = ast.ProcType{ .params = params, .token = tok } };
    }

    fn parse_type_list(self: *Parser) !std.ArrayList(*ast.Type) {
        var types: std.ArrayList(*ast.Type) = .empty;

        const first = try self.lexer.peek_token();
        if (first.type == token.TokenType.r_paren) {
            _ = try self.lexer.next();
            return types;
        }

        while (true) {
            try types.append(self.allocator, try self.parse_type());

            const sep = try self.lexer.next();
            switch (sep.type) {
                .r_paren => break,
                .comma => {
                    const nxt = try self.lexer.peek_token();
                    if (nxt.type == token.TokenType.r_paren) {
                        _ = try self.lexer.next();
                        break;
                    }
                    continue;
                },
                else => {
                    try self.compiler.addError("expected ',' or ')'", err.Severity.Error, sep);

                    try self.sync(&.{ .comma, .r_paren });
                    const hmm = try self.lexer.peek_token();
                    if (hmm.type == .comma) {
                        _ = try self.lexer.next();
                        continue;
                    } else if (hmm.type == .r_paren) {
                        _ = try self.lexer.next();
                    } else {
                        break;
                    }
                },
            }
        }
        return types;
    }

    fn parse_named_type(self: *Parser, tok: token.Token) !ast.BaseType {
        _ = self;
        _ = tok;
        //todo: implement
    }

    pub fn parse_result(self: *Parser) !*ast.Type {
        return self.parse_type();
    }

    pub fn parse_import_def(self: *Parser) !ast.ImportDef {
        var tok = try self.lexer.next();
        var import_def = ast.ImportDef{ .path = .empty, .token = tok };
        while (true) {
            // expect an ident
            tok = try self.expect(.ident, "expected ident ") orelse token.Token{ .type = .ident, .val = "<error>", .line = tok.line, .col = tok.col };

            try import_def.path.append(self.allocator, tok.val);
            // can be a '.'
            tok = try self.lexer.next();
            if (tok.type == token.TokenType.semicolon) break;
            if (tok.type != token.TokenType.dot) {
                if (tok.type != token.TokenType.dot) {
                    try self.compiler.addError("expected . or ; ", err.Severity.Error, tok);
                    try self.sync(&.{ .semicolon, .kw_import, .kw_func, .kw_const, .kw_var, .kw_type, .kw_extern, .kw_pub, .kw_proc });
                    break;
                }
            }
        }
        return import_def;
    }

    pub fn parse_const_def(self: *Parser) !ast.ConstDef {
        var tok = try self.lexer.next();
        var const_def = ast.ConstDef{
            .is_pub = false,
            .is_global = false,
            .name = "",
            .type_ann = null,
            .value = undefined,
            .token = tok,
        };

        // expect name ident
        tok = try self.expect(.ident, "expected name ident ") orelse token.Token{ .type = .ident, .val = "<error>", .line = tok.line, .col = tok.col };
        const_def.name = tok.val;

        // if ':' parse type
        tok = try self.lexer.peek_token();
        if (tok.type == token.TokenType.colon) {
            _ = try self.lexer.next();
            const_def.type_ann = try self.parse_type();
        }

        // expect '='
        _ = try self.expect(.eq, "expected '='");
        const_def.value = try self.parse_expression();

        // extect ';'
        _ = try self.expect(.semicolon, "expected ';'");

        return const_def;
    }

    pub fn parse_expression(self: *Parser) !*ast.Expr {
        const exp = try self.allocator.create(ast.Expr);
        const tok = try self.lexer.peek_token();
        switch (tok.type) {
            token.TokenType.integer => {
                exp.* = .{ .literal = .{
                    .kind = ast.LiteralKind.integer,
                    .raw = tok.val,
                    .token = tok,
                } };
            },
            else => {
                // TODO
            },
        }

        _ = try self.lexer.next();

        return exp;
    }
};
