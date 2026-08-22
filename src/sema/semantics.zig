const std = @import("std");
const ast = @import("../ast.zig");
const compiler = @import("../compiler.zig");
const scope = @import("scope.zig");

pub const Sema = struct {
    compiler: *compiler.Compiler,
    scope: scope.Scope,

    pub fn init(c: *compiler.Compiler) Sema {
        return .{
            .compiler = c,
            .scope = scope.Scope.init(c.allocator),
        };
    }

    pub fn deinit(self: *Sema) void {
        self.scope.deinit();
    }

    pub fn analyze(self: *Sema) !void {
        std.debug.print("\n-------\nanalyzing semantics!\n--------\n", .{});
        const tree = &self.compiler.ast;

        for (tree.program.items.items) |*item| {
            try self.visit_item(item);
        }
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
                self.scope.declare(.{ .name = v.name, .kind = .variable }) catch |err| {
                    if (err == error.DuplicateName) {
                        //todo: implement good error for these, with line numbers
                        //info/hint etc. ?
                        std.debug.print("Duplicate declaration: {s}\n", .{v.name});
                    }
                };
                try self.visit_expression(v.value);
            },
            .const_def => |*c| {
                self.scope.declare(.{ .name = c.name, .kind = .constant }) catch |err| {
                    if (err == error.DuplicateName) {
                        std.debug.print("Duplicate declaration: {s}\n", .{c.name});
                    }
                };
                try self.visit_expression(c.value);
            },
        }
    }

    fn visit_function(self: *Sema, func: *ast.FunctionDef) !void {
        // std.debug.print("visiting function\n", .{});
        try self.visit_type(func.result);

        for (func.params.items) |*param| {
            try self.visit_type(param.type);
        }

        for (func.body.items) |*stmt| {
            try self.visit_statement(stmt);
        }
    }

    fn visit_proc(self: *Sema, func: *ast.ProcDef) !void {
        // std.debug.print("visiting proc\n", .{});
        for (func.params.items) |*param| {
            try self.visit_type(param.type);
        }

        for (func.body.items) |*stmt| {
            try self.visit_statement(stmt);
        }
    }

    fn visit_type(self: *Sema, ty: *ast.Type) !void {
        // std.debug.print("visiting type\n", .{});
        switch (ty.base) {
            .primitive => {},
            .pointer => |inner| try self.visit_type(inner),
            .array => |a| try self.visit_type(a.elem),
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
            },
            .const_stmt => |*c| {
                if (c.type_ann) |ty| try self.visit_type(ty);
                try self.visit_expression(c.value);
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
                for (d.statement_list.items) |*s| {
                    try self.visit_statement(s);
                }
            },
            .unsafe_stmt => |*u| {
                for (u.body.items) |*s| {
                    try self.visit_statement(s);
                }
            },
            .control_flow_stmt => |*c| try self.visit_control_flow(c),
            .return_stmt => |*r| {
                if (r.value) |value| try self.visit_expression(value);
            },
            .expr_stmt => |*e| {
                if (e.value) |value| try self.visit_expression(value);
            },
            .print_stub => {},
        }
    }

    fn visit_control_flow(self: *Sema, stmt: *ast.ControlFlowStmt) !void {
        // std.debug.print("visiting control flow\n", .{});
        switch (stmt.*) {
            .if_expr => |*i| {
                try self.visit_expression(i.cond);
                for (i.then_body.items) |*s| {
                    try self.visit_statement(s);
                }
                for (i.elifs.items) |*e| {
                    try self.visit_expression(e.cond);
                    for (e.body.items) |*s| {
                        try self.visit_statement(s);
                    }
                }
                if (i.else_body) |*body| {
                    for (body.items) |*s| {
                        try self.visit_statement(s);
                    }
                }
            },
            .match_expr => |*m| {
                try self.visit_expression(m.subject);

                for (m.arms.items) |*arm| {
                    for (arm.body.items) |*s| {
                        try self.visit_statement(s);
                    }
                }

                if (m.else_body) |*body| {
                    for (body.items) |*s| {
                        try self.visit_statement(s);
                    }
                }
            },
            .while_expr => |*w| {
                try self.visit_expression(w.cond);
                for (w.body.items) |*s| {
                    try self.visit_statement(s);
                }
            },
            .for_expr => |*f| {
                try self.visit_expression(f.iterable);
                for (f.body.items) |*s| {
                    try self.visit_statement(s);
                }
            },
        }
    }

    fn visit_expression(self: *Sema, expr: *ast.Expr) !void {
        // std.debug.print("visiting expression\n", .{});
        switch (expr.*) {
            .literal, .ident => {},
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
                for (ce.body.items) |*stmt| {
                    try self.visit_statement(stmt);
                }
            },
        }
    }

    // note: so the structure is that we visit these different definitions and all the things
    // like basically make visitors and check for our decided semantics...
    // so progressively we keep developing the semantics here.
};
