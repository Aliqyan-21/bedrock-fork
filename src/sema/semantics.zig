const std = @import("std");
const ast = @import("../ast.zig");
const compiler = @import("../compiler.zig");
const err = @import("../error.zig");
const scope = @import("scope.zig");
const types = @import("type_system.zig");

pub const Sema = struct {
    compiler: *compiler.Compiler,
    scope: *scope.Scope,
    types: types.TypeSystem,

    pub fn init(c: *compiler.Compiler) Sema {
        return .{
            .compiler = c,
            .scope = undefined,
            .types = types.TypeSystem.init(c.allocator),
        };
    }

    pub fn deinit(self: *Sema) void {
        self.types.deinit();
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
            .function => |*f| {
                var param_tys = std.ArrayList(types.TypeId).empty;
                for (f.params.items) |*param| {
                    try param_tys.append(self.compiler.allocator, try self.types.resolve_type(param.type));
                }
                const rty = try self.types.resolve_type(f.result);
                const fnty = try self.types.add(.{ .function = .{ .params = param_tys, .result = rty } });
                self.scope.declare(.{ .name = f.name, .kind = .func, .ty = fnty }) catch |e| {
                    if (e == error.DuplicateName) {
                        try self.compiler.add_sem_error("Duplicate declaration: {s}\n", .{f.name}, .Error, f.token);
                    }
                };
                try self.visit_function(f);
            },
            .proc => |*p| {
                var param_tys = std.ArrayList(types.TypeId).empty;
                for (p.params.items) |*param| {
                    try param_tys.append(self.compiler.allocator, try self.types.resolve_type(param.type));
                }
                const prty = try self.types.add(.{ .procedure = .{ .params = param_tys } });
                self.scope.declare(.{ .name = p.name, .kind = .func, .ty = prty }) catch |e| {
                    if (e == error.DuplicateName) {
                        try self.compiler.add_sem_error("Duplicate declaration: {s}\n", .{p.name}, .Error, p.token);
                    }
                };
                try self.visit_proc(p);
            },
            .struct_def => {},
            .enum_def => {},
            .extern_def => |e_def| {
                switch (e_def.kind) {
                    .func => |f| {
                        self.scope.declare(.{ .name = f.name, .kind = .func }) catch |e| {
                            if (e == error.DuplicateName) {
                                try self.compiler.add_sem_error("Duplicate declaration: {s}\n", .{f.name}, .Error, e_def.token);
                            }
                        };
                    },
                    .proc => |p| {
                        self.scope.declare(.{ .name = p.name, .kind = .func }) catch |e| {
                            if (e == error.DuplicateName) {
                                try self.compiler.add_sem_error("Duplicate declaration: {s}\n", .{p.name}, .Error, e_def.token);
                            }
                        };
                    },
                }
            },
            .var_def => |*v| {
                const dty: types.TypeId = if (v.type_ann) |ty| try self.types.resolve_type(ty) else .invalid;
                const aty = try self.visit_expression(v.value, if (dty != .invalid) dty else null);

                if (dty != .invalid and aty != .invalid and !self.types.assignable(aty, dty)) {
                    try self.compiler.add_sem_error("type mismatch: expected {s}, found {s}", .{ self.types.name_of(dty), self.types.name_of(aty) }, .Error, v.token);
                }
                self.scope.declare(.{ .name = v.name, .kind = .variable, .ty = if (dty != .invalid) dty else aty }) catch |e| {
                    if (e == error.DuplicateName) {
                        try self.compiler.add_sem_error("Duplicate declaration: {s}\n", .{v.name}, .Error, v.token);
                    }
                };
            },
            .const_def => |*c| {
                const dty: types.TypeId = if (c.type_ann) |ty| try self.types.resolve_type(ty) else .invalid;
                const aty = try self.visit_expression(c.value, if (dty != .invalid) dty else null);
                if (dty != .invalid and aty != .invalid and !self.types.assignable(aty, dty)) {
                    try self.compiler.add_sem_error("type mismatch: expected {s}, found {s}", .{ self.types.name_of(dty), self.types.name_of(aty) }, .Error, c.token);
                }
                self.scope.declare(.{ .name = c.name, .kind = .constant, .ty = if (dty != .invalid) dty else aty }) catch |e| {
                    if (e == error.DuplicateName) {
                        try self.compiler.add_sem_error("Duplicate declaration: {s}\n", .{c.name}, .Error, c.token);
                    }
                };
            },
        }
    }

    fn visit_function(self: *Sema, func: *ast.FunctionDef) !void {
        // std.debug.print("visiting function\n", .{});
        const rty = try self.types.resolve_type(func.result);

        var func_scope = scope.Scope.init(self.compiler.allocator, .func, self.scope);
        func_scope.fn_info = .{ .func = rty };
        defer func_scope.deinit();
        const saved = self.scope;
        self.scope = &func_scope;
        defer self.scope = saved;

        for (func.params.items) |*param| {
            const param_ty = try self.types.resolve_type(param.type);
            func_scope.declare(.{ .name = param.name, .kind = .param, .ty = param_ty }) catch |e| {
                if (e == error.DuplicateName) try self.compiler.add_sem_error("Duplicate parameter: {s}\n", .{param.name}, .Error, param.token);
            };
        }

        try self.enter_scope(func.body.items, .block);

        if (rty != .invalid and !self.types.body_returns(func.body.items)) {
            try self.compiler.add_sem_error("control reaches the end of the function", .{}, .Warn, func.token);
        }
    }

    fn visit_proc(self: *Sema, proc: *ast.ProcDef) !void {
        // std.debug.print("visiting proc\n", .{});
        var proc_scope = scope.Scope.init(self.compiler.allocator, .func, self.scope);
        proc_scope.fn_info = .proc;
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
                const dty: types.TypeId = if (v.type_ann) |ty| try self.types.resolve_type(ty) else .invalid;
                const aty = try self.visit_expression(v.value, if (dty != .invalid) dty else null);

                if (dty != .invalid and aty != .invalid and !self.types.assignable(aty, dty)) {
                    try self.compiler.add_sem_error("type mismatch: expected {s}, found {s}", .{ self.types.name_of(dty), self.types.name_of(aty) }, .Error, v.token);
                }
                self.scope.declare(.{ .name = v.name, .kind = .variable, .ty = if (dty != .invalid) dty else aty }) catch |e| {
                    if (e == error.DuplicateName) try self.compiler.add_sem_error("Duplicate declaration: {s}\n", .{v.name}, .Error, v.token);
                };
            },
            .const_stmt => |*c| {
                const dty: types.TypeId = if (c.type_ann) |ty| try self.types.resolve_type(ty) else .invalid;
                const aty = try self.visit_expression(c.value, if (dty != .invalid) dty else null);
                if (dty != .invalid and aty != .invalid and !self.types.assignable(aty, dty)) {
                    try self.compiler.add_sem_error("type mismatch: expected {s}, found {s}", .{ self.types.name_of(dty), self.types.name_of(aty) }, .Error, c.token);
                }
                self.scope.declare(.{ .name = c.name, .kind = .variable, .ty = if (dty != .invalid) dty else aty }) catch |e| {
                    if (e == error.DuplicateName) try self.compiler.add_sem_error("Duplicate declaration: {s}\n", .{c.name}, .Error, c.token);
                };
            },
            .local_static_var_stmt => |lv| {
                if (lv.type_ann) |ty| try self.visit_type(ty);
                _ = try self.visit_expression(lv.value, null);
            },
            .assign_stmt => |*a| {
                const is_discard = a.target.* == .ident and std.mem.eql(u8, a.target.ident.name, "_");
                if (is_discard) {
                    _ = try self.visit_expression(a.value, null);
                } else {
                    _ = try self.visit_expression(a.target, null);
                    _ = try self.visit_expression(a.value, null);
                }
            },
            .defer_stmt => |*d| {
                try self.enter_scope(d.statement_list.items, .block);
            },
            .unsafe_stmt => |*u| {
                try self.enter_scope(u.body.items, .unsafe);
            },
            .control_flow_stmt => |*c| try self.visit_control_flow(c),
            .return_stmt => |*r| {
                const fn_scope = self.scope.enclosing(.func);
                // note: should we handle nil explicitly ??
                if (fn_scope == null) {
                    try self.compiler.add_sem_error("return used outside of function\n", .{}, .Error, r.token);
                    _ = if (r.value) |val| try self.visit_expression(val, null);
                } else if (fn_scope.?.fn_info) |i| switch (i) {
                    .func => |rty| {
                        if (r.value) |val| {
                            const vty = try self.visit_expression(val, if (rty != .invalid) rty else null);
                            if (rty != .invalid and !self.types.assignable(vty, rty)) {
                                try self.compiler.add_sem_error("type mismatch expected {s}, found {s}", .{ self.types.name_of(rty), self.types.name_of(vty) }, .Error, r.token);
                            }
                        } else {
                            try self.compiler.add_sem_error("return should return a value of type {s}", .{self.types.name_of(rty)}, .Error, r.token);
                        }
                    },
                    .proc => {
                        if (r.value) |val| {
                            _ = try self.visit_expression(val, null);
                            try self.compiler.add_sem_error("proc cannot return a value", .{}, .Error, r.token);
                        }
                    },
                };
                _ = if (r.value) |value| try self.visit_expression(value, null);
            },
            .expr_stmt => |*e| {
                if (e.value) |val| {
                    const ty = try self.visit_expression(val, null);
                    // info: I could check here func/proc as func have
                    // to always return a value and proc could never
                    // but .invalid already does that shit if u think of it
                    const is_wrong = ty != .invalid and val.* == .call;
                    if (is_wrong) try self.compiler.add_sem_error("unused return value: use '_ = ...' to discard", .{}, .Error, val.call.token);
                }
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
                _ = try self.visit_expression(i.cond, null);
                try self.enter_scope(i.then_body.items, .block);
                for (i.elifs.items) |*e| {
                    _ = try self.visit_expression(e.cond, null);
                    try self.enter_scope(e.body.items, .block);
                }
                if (i.else_body) |*body| {
                    try self.enter_scope(body.items, .block);
                }
            },
            .match_expr => |*m| {
                _ = try self.visit_expression(m.subject, null);

                for (m.arms.items) |*arm| {
                    try self.enter_scope(arm.body.items, .block);
                }

                if (m.else_body) |*body| {
                    try self.enter_scope(body.items, .block);
                }
            },
            .while_expr => |*w| {
                _ = try self.visit_expression(w.cond, null);
                try self.enter_scope(w.body.items, .loop);
            },
            .for_expr => |*f| {
                _ = try self.visit_expression(f.iterable, null);
                try self.enter_scope(f.body.items, .loop);
            },
        }
    }

    fn visit_expression(self: *Sema, expr: *ast.Expr, expected: ?types.TypeId) !types.TypeId {
        // std.debug.print("visiting expression\n", .{});
        return switch (expr.*) {
            .literal => |*lit| blk: {
                if (expected) |exp| {
                    if (self.types.literal_fits(lit.kind, exp)) break :blk exp;
                }
                break :blk try self.types.literal_type(lit.kind);
            },
            .ident => |i| blk: {
                const sym = self.scope.resolve(i.name) orelse {
                    try self.compiler.add_sem_error("Unknown identifier '{s}'", .{i.name}, .Error, i.token);
                    break :blk .invalid;
                };
                break :blk sym.ty;
            },
            .binary => |*b| {
                _ = try self.visit_expression(b.lhs, null);
                _ = try self.visit_expression(b.rhs, null);
                return .invalid; // todo: implement binary type
            },
            .unary => |*u| blk: {
                switch (u.op) {
                    .neg => {
                        const ty = try self.visit_expression(u.operand, expected);
                        if (ty != .invalid and !self.types.literal_fits(.integer, ty)) {
                            try self.compiler.add_sem_error("cannot negate non-numeric type {s}", .{self.types.name_of(ty)}, .Error, u.token);
                        }
                        break :blk ty;
                    },
                    .not => {
                        const ty = try self.visit_expression(u.operand, try self.types.primitive(.bool));
                        if (ty != .invalid and !self.types.assignable(ty, try self.types.primitive(.bool))) {
                            try self.compiler.add_sem_error("expected a bool, but found {s}", .{self.types.name_of(ty)}, .Error, u.token);
                        }
                        break :blk try self.types.primitive(.bool);
                    },
                    .bit_not => {
                        const ty = try self.visit_expression(u.operand, expected);
                        if (ty != .invalid) {
                            const is_int = switch (self.types.get(ty).*) {
                                .primitive => |p| switch (p) {
                                    .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .usize, .isize => true,
                                    else => false,
                                },
                                else => false,
                            };
                            if (!is_int) {
                                try self.compiler.add_sem_error("cannot bitwise-not non-integer type {s}", .{self.types.name_of(ty)}, .Error, u.token);
                            }
                        }
                        break :blk ty;
                    },
                    .addr_of => {
                        //todo: implement when pointer is implemented
                        _ = try self.visit_expression(u.operand, null);
                        break :blk .invalid;
                    },
                    .deref => {
                        //todo: implement when pointer is implemented
                        _ = try self.visit_expression(u.operand, null);
                        break :blk .invalid;
                    },
                }
                return .invalid; // todo: implement unary type
            },
            .field_access => |*f| {
                _ = try self.visit_expression(f.target, null);
                return .invalid; // todo: implement field_access type?
            },
            .call => |*c| blk: {
                const cty = try self.visit_expression(c.callee, null);
                for (c.args.items) |arg| {
                    _ = try self.visit_expression(arg.value, null);
                }
                if (cty == .invalid) break :blk .invalid;

                break :blk switch (self.types.get(cty).*) {
                    .function => |fnty| result: {
                        if (c.args.items.len != fnty.params.items.len) {
                            try self.compiler.add_sem_error("expected {d} arguments, found {d}", .{ fnty.params.items.len, c.args.items.len }, .Error, c.token);
                            break :result fnty.result;
                        }
                        for (c.args.items, fnty.params.items) |arg, pty| {
                            const argty = try self.visit_expression(arg.value, pty);
                            if (argty != .invalid and !self.types.assignable(argty, pty)) {
                                try self.compiler.add_sem_error("type mismatch: expected {s}, found {s}", .{ self.types.name_of(pty), self.types.name_of(argty) }, .Error, c.token);
                            }
                        }
                        break :result fnty.result;
                    },
                    .procedure => |prty| result: {
                        if (c.args.items.len != prty.params.items.len) {
                            try self.compiler.add_sem_error("expected {d} arguments, found {d}", .{ prty.params.items.len, c.args.items.len }, .Error, c.token);
                        } else {
                            for (c.args.items, prty.params.items) |arg, pty| {
                                const argty = try self.visit_expression(arg.value, pty);
                                if (argty != .invalid and !self.types.assignable(argty, pty)) {
                                    try self.compiler.add_sem_error("type mismatch: expected {s}, found {s}", .{ self.types.name_of(pty), self.types.name_of(argty) }, .Error, c.token);
                                }
                            }
                        }
                        // note: is "a = foo(...)", where foo is a proc should be legal?
                        break :result .invalid;
                    },
                    else => result: {
                        try self.compiler.add_sem_error("cannot call non-function type {s}", .{self.types.name_of(cty)}, .Error, c.token);
                        break :result .invalid;
                    },
                };
            },
            .index => |*i| {
                _ = try self.visit_expression(i.target, null);
                for (i.args.items) |arg| {
                    _ = try self.visit_expression(arg, null);
                }
                return .invalid; //todo: index type
            },
            .optional_unwrap => |*o| {
                _ = try self.visit_expression(o.operand, null);
                return .invalid; //todo: optianal type
            },
            .array_literal => |*al| {
                for (al.elements.items) |elem| {
                    _ = try self.visit_expression(elem, null);
                }
                return .invalid; //todo: array type
            },
            .comptime_expr => |*ce| {
                try self.enter_scope(ce.body.items, .block);
                return .invalid; //todo: comptime type
            },
        };
    }

    // note: so the structure is that we visit these different definitions and all the things
    // like basically make visitors and check for our decided semantics...
    // so progressively we keep developing the semantics here.
};
