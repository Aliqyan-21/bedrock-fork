const std = @import("std");
const ast = @import("../ast.zig");
const compiler = @import("../compiler.zig");

pub const Sema = struct {
    compiler: *compiler.Compiler,

    pub fn init(c: *compiler.Compiler) Sema {
        return .{
            .compiler = c,
        };
    }

    pub fn analyze(self: *Sema) !void {
        std.debug.print("\n-------\nanalyzing semantics!\n--------\n", .{});
        const tree = &self.compiler.ast;

        for (tree.program.items.items) |*item| {
            try visit_item(item);
        }
    }

    fn visit_item(item: *ast.Item) !void {
        switch (item.*) {
            .import_def => {},
            .function => |*f| try visit_function(f),
            .proc => |*p| try visit_proc(p),
            .struct_def => {},
            .enum_def => {},
            .extern_def => {},
            .var_def => |*v| try visit_expression(v.value),
            .const_def => |*c| try visit_expression(c.value),
        }
    }

    fn visit_function(func: *ast.FunctionDef) !void {
        std.debug.print("visiting function\n", .{});
        try visit_type(func.result);

        for (func.params.items) |*param| {
            try visit_type(param.type);
        }

        for (func.body.items) |*stmt| {
            try visit_statement(stmt);
        }
    }

    fn visit_proc(func: *ast.ProcDef) !void {
        std.debug.print("visiting proc\n", .{});
        for (func.params.items) |*param| {
            try visit_type(param.type);
        }

        for (func.body.items) |*stmt| {
            try visit_statement(stmt);
        }
    }

    fn visit_type(ty: *ast.Type) !void {
        std.debug.print("visiting type\n", .{});
        switch (ty.base) {
            .primitive => {},
            .pointer => |inner| try visit_type(inner),
            .array => |a| try visit_type(a.elem),
            .named => |*named| {
                for (named.args) |arg| {
                    try visit_type(arg);
                }
            },
            .func => |*func| {
                for (func.params.items) |p| {
                    try visit_type(p);
                }
            },
            .proc => |*proc| {
                for (proc.params.items) |p| {
                    try visit_type(p);
                }
            },
        }
    }

    fn visit_statement(stmt: *ast.Stmt) !void {
        switch (stmt.*) {
            .var_stmt => {},
            .const_stmt => {},
            .local_static_var_stmt => {},
            .assign_stmt => {},
            .defer_stmt => {},
            .unsafe_stmt => {},
            .control_flow_stmt => {},
            .return_stmt => {},
            .expr_stmt => {},
        }
    }

    fn visit_expression(expr: *ast.Expr) !void {
        std.debug.print("visiting expression\n", .{});
        switch (expr.*) {
            .literal, .ident => {},
            .binary => |*b| {
                try visit_expression(b.lhs);
                try visit_expression(b.rhs);
            },
            .unary => |*u| {
                try visit_expression(u.operand);
            },
            .field_access => |*f| {
                try visit_expression(f.target);
            },
            .call => |*c| {
                try visit_expression(c.callee);
                for (c.args.items) |arg| {
                    try visit_expression(arg.value);
                }
            },
            .index => |*i| {
                try visit_expression(i.target);
                for (i.args.items) |arg| {
                    try visit_expression(arg);
                }
            },
            .optional_unwrap => |*o| {
                try visit_expression(o.operand);
            },
            .array_literal => |*al| {
                for (al.elements.items) |elem| {
                    try visit_expression(elem);
                }
            },
            .comptime_expr => |*ce| {
                for (ce.body.items) |*stmt| {
                    try visit_statement(stmt);
                }
            },
        }
    }

    // note: so the structure is that we visit these different definitions and all the things
    // like basically make visitors and check for our decided semantics...
    // so progressively we keep developing the semantics here.
};
