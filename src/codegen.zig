const std = @import("std");
const llvm = @import("llvm");
const compiler = @import("compiler.zig");
const ast = @import("ast.zig");
const token = @import("token.zig");

pub const Codegen = struct {
    allocator: std.mem.Allocator,
    compiler: *compiler.Compiler,
    ctx: llvm.LLVMContextRef,
    mod: llvm.LLVMModuleRef,
    builder: llvm.LLVMBuilderRef,
    entry: llvm.LLVMBasicBlockRef,
    stack_map: std.StringHashMap(llvm.LLVMValueRef),

    pub fn init(allocator: std.mem.Allocator, c: *compiler.Compiler) Codegen {
        return Codegen{
            .allocator = allocator,
            .compiler = c,
            .ctx = llvm.LLVMContextCreate(),
            .mod = undefined,
            .builder = llvm.LLVMCreateBuilder(),
            .entry = undefined,
            .stack_map = std.StringHashMap(llvm.LLVMValueRef).init(allocator),
        };
    }

    pub fn deinit(self: *Codegen) void {
        self.stack_map.deinit();
    }

    pub fn codegen(self: *Codegen) !llvm.LLVMModuleRef {
        self.mod = llvm.LLVMModuleCreateWithNameInContext("module", self.ctx);
        try self.codegen_program(self.compiler.ast.program);

        // set the pass managers
        const options: llvm.LLVMPassBuilderOptionsRef = llvm.LLVMCreatePassBuilderOptions();
        _ = llvm.LLVMRunPasses(self.mod, "function(sroa,instcombine,simplifycfg)", null, options);

        return self.mod;
    }

    pub fn codegen_program(self: *Codegen, program: ast.Program) !void {
        try self.codegen_items(program.items);
    }

    pub fn codegen_items(self: *Codegen, items: std.ArrayList(ast.Item)) !void {
        for (items.items) |*item| {
            switch (item.*) {
                .function => |*f| try self.codegen_function(f),
                .proc => |*p| try self.codegen_proc(p),
                .extern_def => |*e| try self.codegen_extern(e),
                else => {
                    // TODO:
                },
            }
        }
    }

    pub fn codegen_function(self: *Codegen, function: *ast.FunctionDef) !void {
        const ret_type = try self.get_type(function.result);
        const params = try self.codegen_params(function.params);
        defer self.allocator.free(params);
        const params_len: c_uint = @intCast(function.params.items.len);
        const func_type: llvm.LLVMTypeRef = llvm.LLVMFunctionType(ret_type, params.ptr, params_len, 0);
        const name = try self.allocator.dupeZ(u8, function.name);
        defer self.allocator.free(name);
        const main_func: llvm.LLVMValueRef = llvm.LLVMAddFunction(self.mod, name.ptr, func_type);
        if (main_func != null) {
            std.debug.print("add function {s} to module\n", .{name});
        }

        // set function arg names
        for (function.params.items, 0..) |p, idx| {
            const arg = llvm.LLVMGetParam(main_func, @intCast(idx));
            llvm.LLVMSetValueName2(arg, @ptrCast(p.name), p.name.len);
        }

        self.entry = llvm.LLVMAppendBasicBlock(main_func, "entry");
        llvm.LLVMPositionBuilderAtEnd(self.builder, self.entry);

        // store params on stack
        self.stack_map.clearRetainingCapacity();
        for (function.params.items, 0..) |p, idx| {
            // allocate the space on stack
            const alloca = try self.codegen_alloca(main_func, p);
            const arg = llvm.LLVMGetParam(main_func, @intCast(idx));
            // store value on stack space
            _ = llvm.LLVMBuildStore(self.builder, arg, alloca);
            try self.stack_map.put(p.name, alloca);
        }

        // reset the builder position
        // llvm.LLVMPositionBuilderAtEnd(self.builder, self.entry);

        _ = try self.codegen_statements(function.body);
    }

    pub fn codegen_proc(self: *Codegen, proc: *ast.ProcDef) !void {
        const ret_type = llvm.LLVMVoidType();
        const params = try self.codegen_params(proc.params);
        defer self.allocator.free(params);
        const params_len: c_uint = @intCast(proc.params.items.len);
        const func_type: llvm.LLVMTypeRef = llvm.LLVMFunctionType(ret_type, params.ptr, params_len, 0);
        const name = try self.allocator.dupeZ(u8, proc.name);
        defer self.allocator.free(name);
        const main_func: llvm.LLVMValueRef = llvm.LLVMAddFunction(self.mod, name.ptr, func_type);
        if (main_func != null) {
            std.debug.print("add proc {s} to module\n", .{name});
        }

        // set function arg names
        for (proc.params.items, 0..) |p, idx| {
            const arg = llvm.LLVMGetParam(main_func, @intCast(idx));
            llvm.LLVMSetValueName2(arg, @ptrCast(p.name), p.name.len);
        }

        self.entry = llvm.LLVMAppendBasicBlock(main_func, "entry");
        llvm.LLVMPositionBuilderAtEnd(self.builder, self.entry);

        // store params on stack
        self.stack_map.clearRetainingCapacity();
        for (proc.params.items, 0..) |p, idx| {
            // allocate the space on stack
            const alloca = try self.codegen_alloca(main_func, p);
            const arg = llvm.LLVMGetParam(main_func, @intCast(idx));
            // store value on stack space
            _ = llvm.LLVMBuildStore(self.builder, arg, alloca);
            try self.stack_map.put(p.name, alloca);
        }

        // reset the builder position
        // llvm.LLVMPositionBuilderAtEnd(self.builder, self.entry);

        _ = try self.codegen_statements(proc.body);

        // end proc with void return
        _ = llvm.LLVMBuildRetVoid(self.builder);
    }

    pub fn codegen_extern(self: *Codegen, e_def: *ast.ExternDef) !void {
        switch (e_def.kind) {
            .func => try self.codegen_extern_func(e_def),
            .proc => try self.codegen_extern_proc(e_def),
        }
    }

    pub fn codegen_extern_func(self: *Codegen, e: *ast.ExternDef) !void {
        const ret_type = try self.get_type(e.kind.func.result);
        const params = try self.codegen_params(e.kind.func.params);
        defer self.allocator.free(params);
        const params_len: c_uint = @intCast(e.kind.func.params.items.len);
        const func_type: llvm.LLVMTypeRef = llvm.LLVMFunctionType(ret_type, params.ptr, params_len, 0);
        const name = try self.allocator.dupeZ(u8, e.kind.func.name);
        defer self.allocator.free(name);
        const func: llvm.LLVMValueRef = llvm.LLVMAddFunction(self.mod, name.ptr, func_type);
        llvm.LLVMSetLinkage(func, llvm.LLVMExternalLinkage);
        if (func != null) {
            std.debug.print("add extern {s} to module\n", .{name});
        }

        // set function arg names
        for (e.kind.func.params.items, 0..) |p, idx| {
            const arg = llvm.LLVMGetParam(func, @intCast(idx));
            llvm.LLVMSetValueName2(arg, @ptrCast(p.name), p.name.len);
        }
    }

    pub fn codegen_extern_proc(self: *Codegen, e: *ast.ExternDef) !void {
        const ret_type = llvm.LLVMVoidType();
        const params = try self.codegen_params(e.kind.proc.params);
        defer self.allocator.free(params);
        const params_len: c_uint = @intCast(e.kind.proc.params.items.len);
        const func_type: llvm.LLVMTypeRef = llvm.LLVMFunctionType(ret_type, params.ptr, params_len, 0);
        const name = try self.allocator.dupeZ(u8, e.kind.proc.name);
        defer self.allocator.free(name);
        const func: llvm.LLVMValueRef = llvm.LLVMAddFunction(self.mod, name.ptr, func_type);
        llvm.LLVMSetLinkage(func, llvm.LLVMExternalLinkage);
        if (func != null) {
            std.debug.print("add extern {s} to module\n", .{name});
        }

        // set function arg names
        for (e.kind.proc.params.items, 0..) |p, idx| {
            const arg = llvm.LLVMGetParam(func, @intCast(idx));
            llvm.LLVMSetValueName2(arg, @ptrCast(p.name), p.name.len);
        }
    }

    pub fn codegen_statements(self: *Codegen, stmts: std.ArrayList(ast.Stmt)) !llvm.LLVMValueRef {
        var last_value: llvm.LLVMValueRef = undefined;
        for (stmts.items) |*stmt| {
            last_value = switch (stmt.*) {
                .return_stmt => |*r| try self.codegen_return(r),
                .expr_stmt => |*e| try self.codegen_expression_statement(e),
                .var_stmt => |*v| try self.codegen_var(v),
                .const_stmt => |*c| try self.codegen_const(c),
                .assign_stmt => |*a| try self.codegen_assign(a),
                .control_flow_stmt => |*c| try self.codegen_control_flow(c),
                else => {
                    // TODO:
                    unreachable;
                },
            };
        }

        return last_value;
    }

    pub fn codegen_control_flow(self: *Codegen, cf: *ast.ControlFlowStmt) anyerror!llvm.LLVMValueRef {
        switch (cf.*) {
            .if_expr => |*i| return try self.codegen_if(i),
            else => {
                // TODO:
                unreachable;
            },
        }
    }

    pub fn codegen_if(self: *Codegen, i: *ast.IfExpr) !llvm.LLVMValueRef {
        const cond = try self.codegen_expression(i.cond);

        // get the parent function for block insertion
        const func = llvm.LLVMGetBasicBlockParent(self.entry);
        // TODO: no elif for now
        const then_bb = llvm.LLVMAppendBasicBlock(func, "then");
        const else_bb = llvm.LLVMAppendBasicBlock(func, "else");
        const merge_bb = llvm.LLVMAppendBasicBlock(func, "merge");

        // build cmp condition
        _ = llvm.LLVMBuildCondBr(self.builder, cond, then_bb, else_bb);

        // set new insert point for then_bb codegen
        llvm.LLVMPositionBuilderAtEnd(self.builder, then_bb);
        const then_val = try self.codegen_statements(i.then_body);
        _ = llvm.LLVMBuildBr(self.builder, merge_bb);

        // reset the insert pos
        llvm.LLVMPositionBuilderAtEnd(self.builder, self.entry);

        // set new insert point for else_bb codegen
        llvm.LLVMPositionBuilderAtEnd(self.builder, else_bb);
        const else_val = try self.codegen_statements(i.else_body.?);
        _ = llvm.LLVMBuildBr(self.builder, merge_bb);

        // codegen merge block
        llvm.LLVMPositionBuilderAtEnd(self.builder, merge_bb);
        // const phi = llvm.LLVMBuildPhi(self.builder, llvm.LLVMInt32Type(), "");
        _ = [_]llvm.LLVMValueRef{ then_val, else_val };
        _ = [_]llvm.LLVMBasicBlockRef{ then_bb, else_bb };
        // _ = llvm.LLVMAddIncoming(phi, @ptrCast(@constCast(&values)), @ptrCast(@constCast(&blocks)), 2);

        return else_val;
    }

    pub fn codegen_assign(self: *Codegen, a: *ast.AssignStmt) !llvm.LLVMValueRef {
        const e = try self.codegen_expression(a.value);
        // NOTE: currently only for var assign
        switch (a.target.*) {
            .ident => |*i| {
                // lookup for var on stack
                const alloca = self.stack_map.get(i.name).?;
                _ = llvm.LLVMBuildStore(self.builder, e, alloca);
                return alloca;
            },
            else => {
                // TODO:
                return null;
                // unreachable;
            },
        }
    }

    pub fn codegen_var(self: *Codegen, v: *ast.VarStmt) !llvm.LLVMValueRef {
        const alloca = try self.codegen_alloca_var(v);
        const e = try self.codegen_expression(v.value);
        // store value on stack space
        _ = llvm.LLVMBuildStore(self.builder, e, alloca);
        try self.stack_map.put(v.name, alloca);
        return e;
    }

    pub fn codegen_const(self: *Codegen, v: *ast.ConstStmt) !llvm.LLVMValueRef {
        const alloca = try self.codegen_alloca_const(v);
        const e = try self.codegen_expression(v.value);
        // store value on stack space
        _ = llvm.LLVMBuildStore(self.builder, e, alloca);
        try self.stack_map.put(v.name, alloca);
        return e;
    }

    pub fn codegen_alloca_var(self: *Codegen, v: *ast.VarStmt) !llvm.LLVMValueRef {
        // NOTE: currently type is expected
        const t = try self.get_type(v.type_ann.?);
        const name = try self.allocator.dupeZ(u8, v.name);
        defer self.allocator.free(name);
        return llvm.LLVMBuildAlloca(self.builder, t, name);
    }

    pub fn codegen_alloca_const(self: *Codegen, v: *ast.ConstStmt) !llvm.LLVMValueRef {
        // NOTE: currently type is expected
        const t = try self.get_type(v.type_ann.?);
        const name = try self.allocator.dupeZ(u8, v.name);
        defer self.allocator.free(name);
        return llvm.LLVMBuildAlloca(self.builder, t, name);
    }

    pub fn codegen_params(self: *Codegen, params: std.ArrayList(ast.Param)) ![]llvm.LLVMTypeRef {
        const p_types = try self.allocator.alloc(llvm.LLVMTypeRef, params.items.len);
        for (params.items, 0..) |param, idx| {
            const t = try self.get_type(param.type);
            p_types[idx] = t;
        }

        return p_types;
    }

    pub fn codegen_alloca(self: *Codegen, func: llvm.LLVMValueRef, p: ast.Param) !llvm.LLVMValueRef {
        // get the entry bb
        const e_bb = llvm.LLVMGetEntryBasicBlock(func);
        _ = e_bb;
        // NOTE: no need for first inst only handles for params now
        // get the first inst of entry bb and append the allocas here
        // const i = llvm.LLVMGetFirstInstruction(e_bb);
        // llvm.LLVMPositionBuilderBefore(self.builder, i);
        // TODO: only handles int types for now
        const t = try self.get_type(p.type);
        const name = try self.allocator.dupeZ(u8, p.name);
        defer self.allocator.free(name);
        return llvm.LLVMBuildAlloca(self.builder, t, name);
    }

    pub fn codegen_return(self: *Codegen, r: *ast.ReturnStmt) !llvm.LLVMValueRef {
        if (r.value) |e| {
            const val = try self.codegen_expression(e);
            return llvm.LLVMBuildRet(self.builder, val);
        }
        unreachable;
    }

    pub fn codegen_expression_statement(self: *Codegen, e_stmt: *ast.ExprStmt) !llvm.LLVMValueRef {
        if (e_stmt.value) |e| {
            return try self.codegen_expression(e);
        }
        unreachable;
    }

    pub fn codegen_expression(self: *Codegen, e: *ast.Expr) !llvm.LLVMValueRef {
        return switch (e.*) {
            .literal => |*l| self.codegen_literal(l),
            .binary => |*b| self.codegen_binary(b),
            .unary => |*u| self.codegen_unary(u),
            .call => |*c| self.codegen_call(c),
            .ident => |*i| self.codegen_ident(i),
            else => unreachable,
        };
    }

    pub fn codegen_ident(self: *Codegen, i: *ast.IdentExpr) !llvm.LLVMValueRef {
        // load var from stack
        if (self.stack_map.get(i.name)) |v| {
            return llvm.LLVMBuildLoad2(self.builder, llvm.LLVMGetAllocatedType(v), v, "");
        } else {
            std.debug.print("variable not found\n", .{});
        }

        // TODO: error
        unreachable;
    }

    pub fn codegen_call(self: *Codegen, c: *ast.CallExpr) !llvm.LLVMValueRef {
        // NOTE: assume callee is an ident
        const name = switch (c.callee.*) {
            .ident => |*i| i.name,
            else => {
                // TODO:
                unreachable;
            },
        };

        const name_call = try self.allocator.dupeZ(u8, name);
        defer self.allocator.free(name_call);
        const func_ref = llvm.LLVMGetNamedFunction(self.mod, name_call.ptr);
        if (func_ref == null) {
            std.debug.print("no function named {s}\n", .{name});
        }

        // see why called value type failed here
        const func_type = llvm.LLVMGlobalGetValueType(func_ref);
        if (func_type == null) {
            std.debug.print("no function type for {s}\n", .{name});
        }

        const args = try self.codegen_args(c.args);
        defer self.allocator.free(args);
        const n_args = c.args.items.len;

        const expected = llvm.LLVMCountParamTypes(func_type);
        if (expected != n_args) {
            std.debug.print("expected args = {}, actual args = {}\n", .{ expected, n_args });
        }

        const call = llvm.LLVMBuildCall2(
            self.builder,
            func_type,
            func_ref,
            args.ptr,
            @intCast(n_args),
            @ptrCast(""),
            // name_call,
        );

        return call;
    }

    pub fn codegen_args(self: *Codegen, args: std.ArrayList(ast.CallArg)) ![]llvm.LLVMValueRef {
        const a = try self.allocator.alloc(llvm.LLVMValueRef, args.items.len);
        for (args.items, 0..) |arg, idx| {
            const v = try self.codegen_expression(arg.value);
            a[idx] = v;
        }

        return a;
    }

    // pub fn codegen_ident(self: *codegen, i: *ast.IdentExpr) !llvm.LLVMValueRef {}

    pub fn codegen_literal(self: *Codegen, l: *ast.LiteralExpr) !llvm.LLVMValueRef {
        switch (l.kind) {
            .integer => {
                const i = try std.fmt.parseInt(c_ulonglong, l.raw, 10);
                return llvm.LLVMConstInt(llvm.LLVMInt32Type(), i, 1);
            },
            .string => {
                const name = try self.allocator.dupeZ(u8, l.raw);
                defer self.allocator.free(name);
                // TODO: maintain the global string table
                return llvm.LLVMBuildGlobalString(self.builder, name, ".str0");
            },
            else => {
                // TODO:
                unreachable;
            },
        }
    }

    pub fn codegen_binary(self: *Codegen, b: *ast.BinaryExpr) anyerror!llvm.LLVMValueRef {
        const l = try self.codegen_expression(b.lhs);
        const r = try self.codegen_expression(b.rhs);
        // TODO: handle overflow and underflow
        return switch (b.op) {
            .add => llvm.LLVMBuildAdd(self.builder, l, r, "add_bin"),
            .sub => llvm.LLVMBuildSub(self.builder, l, r, "sub_bin"),
            .mul => llvm.LLVMBuildMul(self.builder, l, r, "mul_bin"),
            .div => llvm.LLVMBuildUDiv(self.builder, l, r, "div_bin"),
            .mod => llvm.LLVMBuildURem(self.builder, l, r, "mod_bin"),
            .eq => llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntEQ, l, r, "cmp_bin"),
            .ne => llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntNE, l, r, "cmp_bin"),
            .lt => llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntULT, l, r, "cmp_bin"),
            .gt => llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntUGT, l, r, "cmp_bin"),
            .le => llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntULE, l, r, "cmp_bin"),
            .ge => llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntUGE, l, r, "cmp_bin"),
            .bit_or => llvm.LLVMBuildOr(self.builder, l, r, "log_bin"),
            .bit_xor => llvm.LLVMBuildXor(self.builder, l, r, "log_bin"),
            .bit_and => llvm.LLVMBuildAnd(self.builder, l, r, "log_bin"),
            .shl => llvm.LLVMBuildShl(self.builder, l, r, "shift_bin"),
            .shr => llvm.LLVMBuildLShr(self.builder, l, r, "shift_bin"),
            else => {
                // TODO:
                unreachable;
            },
        };
    }

    pub fn codegen_unary(self: *Codegen, u: *ast.UnaryExpr) anyerror!llvm.LLVMValueRef {
        const e = try self.codegen_expression(u.operand);
        return switch (u.op) {
            .neg => llvm.LLVMBuildNeg(self.builder, e, "neg_un"),
            .bit_not => llvm.LLVMBuildNot(self.builder, e, "bit_not_un"),
            else => {
                // TODO:
                unreachable;
            },
        };
    }

    pub fn get_type(self: *Codegen, ret_type: *ast.Type) !llvm.LLVMTypeRef {
        // TODO: handle optionals and errors
        switch (ret_type.base) {
            .primitive => |*p| return self.get_primitive_type(p),
            else => {
                // TODO:
                unreachable;
            },
        }
    }

    pub fn get_primitive_type(self: *Codegen, p: *ast.PrimitiveType) !llvm.LLVMTypeRef {
        _ = self;
        switch (p.*) {
            .i32 => return llvm.LLVMInt32Type(),
            .str => return llvm.LLVMPointerType(llvm.LLVMInt8Type(), 64),
            else => {
                // TODO:
                unreachable;
            },
        }
    }
};
