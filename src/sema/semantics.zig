const std = @import("std");
const ast = @import("../ast.zig");
const compiler = @import("../compiler.zig");
const err = @import("../error.zig");
const scope = @import("scope.zig");

pub const Sema = struct {
    compiler: *compiler.Compiler,
    scope: *scope.Scope,

    pub fn init(c: *compiler.Compiler) Sema {
        return .{
            .compiler = c,
            .scope = undefined,
        };
    }

    pub fn deinit(self: *Sema) void {
        _ = self;
    }

    pub fn analyze(self: *Sema) !void {
        std.debug.print("\n-------\nanalyzing semantics!\n--------\n", .{});
        var root = scope.Scope.init(self.compiler.allocator, .root, null);
        defer root.deinit();
        self.scope = &root;
        const tree = &self.compiler.ast;

        for (tree.program.items.items) |*item| {
            try self.visit_item(item);
        }
    }

    fn enter_scope(self: *Sema, stmts: []ast.Stmt, kind: scope.Scope.Id) !void {
        var block_scope = scope.Scope.init(self.compiler.allocator, kind, self.scope);
        defer block_scope.deinit();

        const saved = self.scope;
        self.scope = &block_scope;
        defer self.scope = saved;

        for (stmts) |*stmt| try self.visit_statement(stmt);
    }

    fn visit_item(self: *Sema, item: *ast.Item) !void {
        switch (item.*) {
            .import_def => {},
            .function => |*f| try self.visit_function(f),
            .proc => |*p| try self.visit_proc(p),
            .struct_def => {},
            .enum_def => {},
            .extern_def => {},
            .var_def => |*v| {
                self.scope.declare(.{ .name = v.name, .kind = .variable }) catch |e| {
                    if (e == error.DuplicateName) {
                        try self.compiler.add_sem_error("Duplicate declaration: {s}\n", .{v.name}, .Error, v.token);
                    }
                };
                try self.visit_expression(v.value);
            },
            .const_def => |*c| {
                self.scope.declare(.{ .name = c.name, .kind = .constant }) catch |e| {
                    if (e == error.DuplicateName) {
                        try self.compiler.add_sem_error("Duplicate declaration: {s}\n", .{c.name}, .Error, c.token);
                    }
                };
                try self.visit_expression(c.value);
            },
        }
    }

    fn visit_function(self: *Sema, func: *ast.FunctionDef) !void {
        // std.debug.print("visiting function\n", .{});
        try self.visit_type(func.result);

        var func_scope = scope.Scope.init(self.compiler.allocator, .func, self.scope);
        defer func_scope.deinit();
        const saved = self.scope;
        self.scope = &func_scope;
        defer self.scope = saved;

        for (func.params.items) |*param| {
            try self.visit_type(param.type);
            func_scope.declare(.{ .name = param.name, .kind = .param }) catch |e| {
                if (e == error.DuplicateName) try self.compiler.add_sem_error("Duplicate parameter: {s}\n", .{param.name}, .Error, param.token);
            };
        }

        try self.enter_scope(func.body.items, .block);
    }

    fn visit_proc(self: *Sema, proc: *ast.ProcDef) !void {
        // std.debug.print("visiting proc\n", .{});
        var proc_scope = scope.Scope.init(self.compiler.allocator, .func, self.scope);
        defer proc_scope.deinit();
        const saved = self.scope;
        self.scope = &proc_scope;
        defer self.scope = saved;

        for (proc.params.items) |*param| {
            try self.visit_type(param.type);
            proc_scope.declare(.{ .name = param.name, .kind = .param }) catch |e| {
                if (e == error.DuplicateName) try self.compiler.add_sem_error("Duplicate parameter: {s}\n", .{param.name}, .Error, param.token);
            };
        }

        try self.enter_scope(proc.body.items, .block);
    }

    fn visit_type(self: *Sema, ty: *ast.Type) !void {
        // std.debug.print("visiting type\n", .{});
        switch (ty.base) {
            .primitive => {},
            .pointer => |inner| try self.visit_type(inner),
            .array => |a| try self.visit_type(a.elem),
            .slice => |s| try self.visit_type(s.elem),
            .named => |*named| {
                for (named.args) |arg| {
                    try self.visit_type(arg);
                }
            },
            .func => |*func| {
                for (func.params.items) |p| {
                    try self.visit_type(p);
                }
            },
            .proc => |*proc| {
                for (proc.params.items) |p| {
                    try self.visit_type(p);
                }
            },
        }
    }

    fn visit_statement(self: *Sema, stmt: *ast.Stmt) anyerror!void {
        // std.debug.print("visiting statement\n", .{});
        switch (stmt.*) {
            .var_stmt => |*v| {
                if (v.type_ann) |ty| try self.visit_type(ty);
                try self.visit_expression(v.value);
                self.scope.declare(.{ .name = v.name, .kind = .variable }) catch |e| {
                    if (e == error.DuplicateName) try self.compiler.add_sem_error("Duplicate declaration: {s}\n", .{v.name}, .Error, v.token);
                };
            },
            .const_stmt => |*c| {
                if (c.type_ann) |ty| try self.visit_type(ty);
                try self.visit_expression(c.value);
                self.scope.declare(.{ .name = c.name, .kind = .variable }) catch |e| {
                    if (e == error.DuplicateName) try self.compiler.add_sem_error("Duplicate declaration: {s}\n", .{c.name}, .Error, c.token);
                };
            },
            .local_static_var_stmt => |lv| {
                if (lv.type_ann) |ty| try self.visit_type(ty);
                try self.visit_expression(lv.value);
            },
            .assign_stmt => |*a| {
                try self.visit_expression(a.target);
                try self.visit_expression(a.value);
            },
            .defer_stmt => |*d| {
                try self.enter_scope(d.statement_list.items, .block);
            },
            .unsafe_stmt => |*u| {
                try self.enter_scope(u.body.items, .unsafe);
            },
            .control_flow_stmt => |*c| try self.visit_control_flow(c),
            .return_stmt => |*r| {
                if (r.value) |value| try self.visit_expression(value);
            },
            .expr_stmt => |*e| {
                if (e.value) |value| try self.visit_expression(value);
            },
            .break_stmt => |*b| {
                if (self.scope.enclosing(.loop) == null) {
                    try self.compiler.add_sem_error("break used outside of loop\n", .{}, .Error, b.token);
                }
            },
            .continue_stmt => |*c| {
                if (self.scope.enclosing(.loop) == null) {
                    try self.compiler.add_sem_error("continue used outside of loop\n", .{}, .Error, c.token);
                }
            },
            else => {},
        }
    }

    fn visit_control_flow(self: *Sema, stmt: *ast.ControlFlowStmt) !void {
        // std.debug.print("visiting control flow\n", .{});
        switch (stmt.*) {
            .if_expr => |*i| {
                try self.visit_expression(i.cond);
                try self.enter_scope(i.then_body.items, .block);
                for (i.elifs.items) |*e| {
                    try self.visit_expression(e.cond);
                    try self.enter_scope(e.body.items, .block);
                }
                if (i.else_body) |*body| {
                    try self.enter_scope(body.items, .block);
                }
            },
            .match_expr => |*m| {
                try self.visit_expression(m.subject);

                for (m.arms.items) |*arm| {
                    try self.enter_scope(arm.body.items, .block);
                }

                if (m.else_body) |*body| {
                    try self.enter_scope(body.items, .block);
                }
            },
            .while_expr => |*w| {
                try self.visit_expression(w.cond);
                try self.enter_scope(w.body.items, .loop);
            },
            .for_expr => |*f| {
                try self.visit_expression(f.iterable);
                try self.enter_scope(f.body.items, .loop);
            },
        }
    }

    fn visit_expression(self: *Sema, expr: *ast.Expr) !void {
        // std.debug.print("visiting expression\n", .{});
        switch (expr.*) {
            .literal => {},
            .ident => |i| {
                if (self.scope.resolve(i.name) == null) {
                    try self.compiler.add_sem_error("Unknown identifier '{s}'", .{i.name}, .Error, i.token);
                }
            },
            .binary => |*b| {
                try self.visit_expression(b.lhs);
                try self.visit_expression(b.rhs);
            },
            .unary => |*u| {
                try self.visit_expression(u.operand);
            },
            .field_access => |*f| {
                try self.visit_expression(f.target);
            },
            .call => |*c| {
                try self.visit_expression(c.callee);
                for (c.args.items) |arg| {
                    try self.visit_expression(arg.value);
                }
            },
            .index => |*i| {
                try self.visit_expression(i.target);
                for (i.args.items) |arg| {
                    try self.visit_expression(arg);
                }
            },
            .optional_unwrap => |*o| {
                try self.visit_expression(o.operand);
            },
            .array_literal => |*al| {
                for (al.elements.items) |elem| {
                    try self.visit_expression(elem);
                }
            },
            .comptime_expr => |*ce| {
                try self.enter_scope(ce.body.items, .block);
            },
        }
    }

    // note: so the structure is that we visit these different definitions and all the things
    // like basically make visitors and check for our decided semantics...
    // so progressively we keep developing the semantics here.
};
