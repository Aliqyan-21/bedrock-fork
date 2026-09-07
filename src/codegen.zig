const std = @import("std");
const llvm = @import("llvm");
const compiler = @import("compiler.zig");
const ast = @import("ast.zig");
const token = @import("token.zig");
const types = @import("sema/type_system.zig");

pub const Codegen = struct {
    allocator: std.mem.Allocator,
    compiler: *compiler.Compiler,
    ctx: llvm.LLVMContextRef,
    mod: llvm.LLVMModuleRef,
    builder: llvm.LLVMBuilderRef,
    entry: llvm.LLVMBasicBlockRef,
    opt: bool,
    stack_map: std.StringHashMap(llvm.LLVMValueRef),
    break_targets: std.ArrayList(llvm.LLVMBasicBlockRef),
    continue_targets: std.ArrayList(llvm.LLVMBasicBlockRef),

    pub fn init(allocator: std.mem.Allocator, c: *compiler.Compiler) Codegen {
        return Codegen{
            .allocator = allocator,
            .compiler = c,
            .ctx = llvm.LLVMContextCreate(),
            .mod = undefined,
            .builder = llvm.LLVMCreateBuilder(),
            .entry = undefined,
            .opt = false,
            .stack_map = std.StringHashMap(llvm.LLVMValueRef).init(allocator),
            .break_targets = .empty,
            .continue_targets = .empty,
        };
    }

    pub fn deinit(self: *Codegen) void {
        self.stack_map.deinit();
        self.break_targets.deinit(self.allocator);
        self.continue_targets.deinit(self.allocator);
    }

    pub fn codegen(self: *Codegen) !llvm.LLVMModuleRef {
        self.mod = llvm.LLVMModuleCreateWithNameInContext("module", self.ctx);
        try self.codegen_program(self.compiler.ast.program);

        // set the pass managers
        if (self.opt) {
            const options: llvm.LLVMPassBuilderOptionsRef = llvm.LLVMCreatePassBuilderOptions();
            _ = llvm.LLVMRunPasses(self.mod, "function(sroa,instcombine,simplifycfg)", null, options);
        }

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
            // std.debug.print("add function {s} to module\n", .{name});
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
            // std.debug.print("add proc {s} to module\n", .{name});
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
        const is_vararg: c_int = if (e.kind.func.is_variadic) 1 else 0;
        const func_type: llvm.LLVMTypeRef = llvm.LLVMFunctionType(ret_type, params.ptr, params_len, is_vararg);
        const name = try self.allocator.dupeZ(u8, e.kind.func.name);
        defer self.allocator.free(name);
        const func: llvm.LLVMValueRef = llvm.LLVMAddFunction(self.mod, name.ptr, func_type);
        llvm.LLVMSetLinkage(func, llvm.LLVMExternalLinkage);
        if (func != null) {
            // std.debug.print("add extern {s} to module\n", .{name});
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
        const is_vararg: c_int = if (e.kind.func.is_variadic) 1 else 0;
        const func_type: llvm.LLVMTypeRef = llvm.LLVMFunctionType(ret_type, params.ptr, params_len, is_vararg);
        const name = try self.allocator.dupeZ(u8, e.kind.proc.name);
        defer self.allocator.free(name);
        const func: llvm.LLVMValueRef = llvm.LLVMAddFunction(self.mod, name.ptr, func_type);
        llvm.LLVMSetLinkage(func, llvm.LLVMExternalLinkage);
        if (func != null) {
            // std.debug.print("add extern {s} to module\n", .{name});
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
                .break_stmt => try self.codegen_break_stmt(),
                .continue_stmt => try self.codegen_continue_stmt(),
                else => {
                    // TODO:
                    unreachable;
                },
            };
        }

        return last_value;
    }

    fn codegen_continue_stmt(self: *Codegen) !llvm.LLVMValueRef {
        const target = self.continue_targets.getLast();
        return llvm.LLVMBuildBr(self.builder, target);
    }

    pub fn codegen_break_stmt(self: *Codegen) !llvm.LLVMValueRef {
        const target = self.break_targets.getLast();
        return llvm.LLVMBuildBr(self.builder, target);
    }

    pub fn codegen_array(self: *Codegen, a: *ast.ArrayLiteralExpr, e: *ast.Expr) anyerror!llvm.LLVMValueRef {
        const array_ty = try self.get_llvm_type_of(self.expr_type(e));
        const arr = llvm.LLVMBuildAlloca(self.builder, array_ty, "");
        var indices = [2]llvm.LLVMValueRef{
            llvm.LLVMConstInt(llvm.LLVMInt64Type(), 0, 0),
            llvm.LLVMConstInt(llvm.LLVMInt64Type(), 0, 0),
        };

        for (a.elements.items, 0..) |ele, idx| {
            indices[1] = llvm.LLVMConstInt(llvm.LLVMInt64Type(), idx, 0);
            const value = try self.codegen_expression(ele);
            const gep = llvm.LLVMBuildGEPWithNoWrapFlags(
                self.builder,
                array_ty,
                arr,
                &indices,
                2,
                "",
                0,
            );

            _ = llvm.LLVMBuildStore(self.builder, value, gep);
        }
        return arr;
    }

    pub fn codegen_control_flow(self: *Codegen, cf: *ast.ControlFlowStmt) anyerror!llvm.LLVMValueRef {
        switch (cf.*) {
            .if_expr => |*i| return try self.codegen_if(i),
            .while_expr => |*w| return try self.codegen_while(w),
            .for_expr => |*f| return try self.codegen_for(f),
            else => {
                // TODO:
                unreachable;
            },
        }
    }

    pub fn codegen_while(self: *Codegen, w: *ast.WhileExpr) !llvm.LLVMValueRef {
        // jmp to while condition block
        const func = llvm.LLVMGetBasicBlockParent(self.entry);

        const cond_bb = llvm.LLVMAppendBasicBlock(func, "cond_bb");
        const while_bb = llvm.LLVMAppendBasicBlock(func, "while_bb");
        const merge_bb = llvm.LLVMAppendBasicBlock(func, "merge");

        _ = llvm.LLVMBuildBr(self.builder, cond_bb);
        llvm.LLVMPositionBuilderAtEnd(self.builder, cond_bb);

        const cond = try self.codegen_expression(w.cond);
        _ = llvm.LLVMBuildCondBr(self.builder, cond, while_bb, merge_bb);

        // reset the insert pos
        llvm.LLVMPositionBuilderAtEnd(self.builder, while_bb);
        try self.break_targets.append(self.allocator, merge_bb);
        const while_val = try self.codegen_statements(w.body);
        _ = self.break_targets.pop();
        _ = llvm.LLVMBuildBr(self.builder, cond_bb);

        // reset the insert pos
        llvm.LLVMPositionBuilderAtEnd(self.builder, merge_bb);

        return while_val;
    }

    pub fn codegen_if(self: *Codegen, i: *ast.IfExpr) !llvm.LLVMValueRef {
        // get the parent function for block insertion
        const func = llvm.LLVMGetBasicBlockParent(self.entry);
        const then_bb = llvm.LLVMAppendBasicBlock(func, "then");
        const merge_bb = llvm.LLVMAppendBasicBlock(func, "merge");

        const elif_bbs = try self.allocator.alloc(llvm.LLVMBasicBlockRef, i.elifs.items.len);
        defer self.allocator.free(elif_bbs);
        const elif_then_bbs = try self.allocator.alloc(llvm.LLVMBasicBlockRef, i.elifs.items.len);
        defer self.allocator.free(elif_then_bbs);
        for (elif_bbs, 0..) |*bb, idx| {
            bb.* = llvm.LLVMAppendBasicBlock(func, "elif_check");
            elif_then_bbs[idx] = llvm.LLVMAppendBasicBlock(func, "elif_then");
        }

        const else_bb = llvm.LLVMAppendBasicBlock(func, "else");

        const first_false_bb = if (elif_bbs.len > 0) elif_bbs[0] else else_bb;
        const cond = try self.codegen_expression(i.cond);
        _ = llvm.LLVMBuildCondBr(self.builder, cond, then_bb, first_false_bb);

        // set new insert point for then_bb codegen
        llvm.LLVMPositionBuilderAtEnd(self.builder, then_bb);
        _ = try self.codegen_statements(i.then_body);
        if (llvm.LLVMGetBasicBlockTerminator(then_bb) == null) {
            _ = llvm.LLVMBuildBr(self.builder, merge_bb);
        }

        for (i.elifs.items, 0..) |*elif, idx| {
            llvm.LLVMPositionBuilderAtEnd(self.builder, elif_bbs[idx]);
            const elif_cond = try self.codegen_expression(elif.cond);
            const nxt = if (idx + 1 < elif_bbs.len) elif_bbs[idx + 1] else else_bb;
            _ = llvm.LLVMBuildCondBr(self.builder, elif_cond, elif_then_bbs[idx], nxt);

            llvm.LLVMPositionBuilderAtEnd(self.builder, elif_then_bbs[idx]);
            _ = try self.codegen_statements(elif.body);
            if (llvm.LLVMGetBasicBlockTerminator(elif_then_bbs[idx]) == null) {
                _ = llvm.LLVMBuildBr(self.builder, merge_bb);
            }
        }

        // set new insert point for else_bb codegen
        llvm.LLVMPositionBuilderAtEnd(self.builder, else_bb);
        if (i.else_body) |*body| {
            _ = try self.codegen_statements(body.*);
        }
        if (llvm.LLVMGetBasicBlockTerminator(else_bb) == null) {
            _ = llvm.LLVMBuildBr(self.builder, merge_bb);
        }

        // codegen merge block
        llvm.LLVMPositionBuilderAtEnd(self.builder, merge_bb);
        // const phi = llvm.LLVMBuildPhi(self.builder, llvm.LLVMInt32Type(), "");
        // _ = [_]llvm.LLVMValueRef{ then_val, else_val };
        // _ = [_]llvm.LLVMBasicBlockRef{ then_bb, else_bb };
        // _ = llvm.LLVMAddIncoming(phi, @ptrCast(@constCast(&values)), @ptrCast(@constCast(&blocks)), 2);

        return null;
    }

    pub fn codegen_array_iter(self: *Codegen, f: *ast.ForExpr, ty: types.TypeId, len: u64) !llvm.LLVMValueRef {
        const llvm_ty = try self.get_llvm_type_of(ty);
        const array_ptr = switch (f.iterable.*) {
            .ident => |ident| self.stack_map.get(ident.name) orelse {
                return error.UnknownVariable;
            },
            else => return error.UnsupportedArrayTarget,
        };

        const l = llvm.LLVMConstInt(llvm.LLVMInt64Type(), len, 0);

        const func = llvm.LLVMGetBasicBlockParent(self.entry);
        const cond_bb = llvm.LLVMAppendBasicBlock(func, "for_cond");
        const body_bb = llvm.LLVMAppendBasicBlock(func, "for_body");
        const merge_bb = llvm.LLVMAppendBasicBlock(func, "for_merge");

        // index variable.
        const index_alloca = llvm.LLVMBuildAlloca(self.builder, llvm.LLVMInt64Type(), "for_index");
        _ = llvm.LLVMBuildStore(
            self.builder,
            llvm.LLVMConstInt(llvm.LLVMInt64Type(), 0, 0),
            index_alloca,
        );

        const name = try self.allocator.dupeZ(u8, f.binding);
        defer self.allocator.free(name);
        const i_alloca = llvm.LLVMBuildAlloca(self.builder, llvm_ty, name);
        try self.stack_map.put(f.binding, i_alloca);

        _ = llvm.LLVMBuildBr(self.builder, cond_bb);

        llvm.LLVMPositionBuilderAtEnd(self.builder, cond_bb);

        const index = llvm.LLVMBuildLoad2(self.builder, llvm.LLVMInt64Type(), index_alloca, "index");
        const cond = llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntULT, index, l, "for_cmp");
        _ = llvm.LLVMBuildCondBr(self.builder, cond, body_bb, merge_bb);

        llvm.LLVMPositionBuilderAtEnd(self.builder, body_bb);

        var indices = [2]llvm.LLVMValueRef{
            llvm.LLVMConstInt(llvm.LLVMInt64Type(), 0, 0),
            index,
        };

        const gep = llvm.LLVMBuildGEPWithNoWrapFlags(
            self.builder,
            llvm.LLVMArrayType2(llvm_ty, len),
            array_ptr,
            &indices,
            2,
            "",
            0,
        );

        const ele = llvm.LLVMBuildLoad2(self.builder, llvm_ty, gep, "ele");
        _ = llvm.LLVMBuildStore(self.builder, ele, i_alloca);

        try self.break_targets.append(self.allocator, merge_bb);
        _ = try self.codegen_statements(f.body);
        _ = self.break_targets.pop();

        // i = i + 1
        const curr = llvm.LLVMBuildLoad2(self.builder, llvm.LLVMInt64Type(), index_alloca, "index");
        const next = llvm.LLVMBuildAdd(
            self.builder,
            curr,
            llvm.LLVMConstInt(llvm.LLVMInt64Type(), 1, 0),
            "for_inc",
        );
        _ = llvm.LLVMBuildStore(self.builder, next, index_alloca);
        _ = llvm.LLVMBuildBr(self.builder, cond_bb);

        llvm.LLVMPositionBuilderAtEnd(self.builder, merge_bb);

        return i_alloca;
    }

    pub fn codegen_for_range(self: *Codegen, f: *ast.ForExpr, ty: types.TypeId) !llvm.LLVMValueRef {
        const llvm_ty = try self.get_llvm_type_of(ty);

        const b = &f.iterable.binary;
        const lo = try self.codegen_expression(b.lhs);
        const hi = try self.codegen_expression(b.rhs);

        const func = llvm.LLVMGetBasicBlockParent(self.entry);
        const cond_bb = llvm.LLVMAppendBasicBlock(func, "for_cond");
        const body_bb = llvm.LLVMAppendBasicBlock(func, "for_body");
        const merge_bb = llvm.LLVMAppendBasicBlock(func, "for_merge");

        const name = try self.allocator.dupeZ(u8, f.binding);
        defer self.allocator.free(name);
        const i_alloca = llvm.LLVMBuildAlloca(self.builder, llvm_ty, name);
        _ = llvm.LLVMBuildStore(self.builder, lo, i_alloca);
        try self.stack_map.put(f.binding, i_alloca);

        _ = llvm.LLVMBuildBr(self.builder, cond_bb);
        llvm.LLVMPositionBuilderAtEnd(self.builder, cond_bb);

        const is_float = switch (self.compiler.sema.types.get(ty).*) {
            .primitive => |p| p == .f32 or p == .f64,
            else => false,
        };
        const is_signed = switch (self.compiler.sema.types.get(ty).*) {
            .primitive => |p| switch (p) {
                .i8, .i16, .i32, .i64, .isize => true,
                else => false,
            },
            else => false,
        };
        const i_val = llvm.LLVMBuildLoad2(self.builder, llvm_ty, i_alloca, "");
        const cond = if (is_float)
            llvm.LLVMBuildFCmp(self.builder, llvm.LLVMRealOLT, i_val, hi, "for_cmp")
        else
            llvm.LLVMBuildICmp(self.builder, if (is_signed) llvm.LLVMIntSLT else llvm.LLVMIntULT, i_val, hi, "for_cmp");

        _ = llvm.LLVMBuildCondBr(self.builder, cond, body_bb, merge_bb);

        llvm.LLVMPositionBuilderAtEnd(self.builder, body_bb);
        try self.break_targets.append(self.allocator, merge_bb);
        _ = try self.codegen_statements(f.body);
        _ = self.break_targets.pop();

        // do the i = i + 1
        const cur = llvm.LLVMBuildLoad2(self.builder, llvm_ty, i_alloca, "");
        const one = if (is_float) llvm.LLVMConstReal(llvm_ty, 1.0) else llvm.LLVMConstInt(llvm_ty, 1, 0);
        const next = if (is_float) llvm.LLVMBuildFAdd(self.builder, cur, one, "for_inc") else llvm.LLVMBuildAdd(self.builder, cur, one, "for_inc");
        _ = llvm.LLVMBuildStore(self.builder, next, i_alloca);
        _ = llvm.LLVMBuildBr(self.builder, cond_bb);

        llvm.LLVMPositionBuilderAtEnd(self.builder, merge_bb);
        return i_alloca;
    }

    pub fn codegen_for(self: *Codegen, f: *ast.ForExpr) !llvm.LLVMValueRef {
        // todo: slices based iterations
        const iter_ty = self.expr_type(f.iterable);
        return switch (self.compiler.sema.types.get(iter_ty).*) {
            .range => |r| try self.codegen_for_range(f, r.elem),
            .array => |a| try self.codegen_array_iter(f, a.child, a.len),
            else => unreachable, // sema sambhal lega
        };
    }

    fn is_signed_type(self: *Codegen, ty: types.TypeId) bool {
        return switch (self.compiler.sema.types.get(ty).*) {
            .primitive => |p| switch (p) {
                .i8, .i16, .i32, .i64, .isize => true,
                .u8, .u16, .u32, .u64, .usize => false,
                else => false,
            },
            else => false,
        };
    }

    pub fn codegen_assign(self: *Codegen, a: *ast.AssignStmt) !llvm.LLVMValueRef {
        const e = try self.codegen_expression(a.value);
        // NOTE: currently only for var assign
        switch (a.target.*) {
            .ident => |*i| {
                if (std.mem.eql(u8, i.name, "_")) {
                    return e; // return if assigning in '_' (it is discard mf)
                }
                // lookup for var on stack
                const alloca = self.stack_map.get(i.name).?;
                if (a.op == null) {
                    _ = llvm.LLVMBuildStore(self.builder, e, alloca);
                    return alloca;
                } else {
                    const target_ty = self.expr_type(a.target);
                    const llvm_target_ty = try self.get_llvm_type_of(target_ty);
                    const old = llvm.LLVMBuildLoad2(self.builder, llvm_target_ty, alloca, "");
                    const is_signed = self.is_signed_type(target_ty);
                    const result = try self.codegen_compound_op(a.op.?, old, e, is_signed);
                    _ = llvm.LLVMBuildStore(self.builder, result, alloca);
                    return alloca;
                }
            },
            .index => |*i| {
                const e_ptr = try self.codegen_array_element_ptr(i);
                if (a.op == null) {
                    _ = llvm.LLVMBuildStore(self.builder, e, e_ptr);
                    return e_ptr;
                } else {
                    const elem_ty = self.expr_type(a.target);
                    const llvm_elem_ty = try self.get_llvm_type_of(elem_ty);
                    const old = llvm.LLVMBuildLoad2(self.builder, llvm_elem_ty, e_ptr, "");
                    const is_signed = self.is_signed_type(elem_ty);
                    const result = try self.codegen_compound_op(a.op.?, old, e, is_signed);
                    _ = llvm.LLVMBuildStore(self.builder, result, e_ptr);
                    return e_ptr;
                }
            },
            else => {
                // TODO:
                return null;
                // unreachable;
            },
        }
    }

    pub fn codegen_var(self: *Codegen, v: *ast.VarStmt) !llvm.LLVMValueRef {
        switch (v.value.*) {
            .array_literal => {
                const arr = try self.codegen_expression(v.value);
                try self.stack_map.put(v.name, arr);
                return arr;
            },
            else => {
                const alloca = try self.codegen_alloca_var(v);
                const e = try self.codegen_expression(v.value);
                // store value on stack space
                _ = llvm.LLVMBuildStore(self.builder, e, alloca);
                try self.stack_map.put(v.name, alloca);
                return e;
            },
        }
    }

    pub fn codegen_const(self: *Codegen, v: *ast.ConstStmt) !llvm.LLVMValueRef {
        switch (v.value.*) {
            .array_literal => {
                const arr = try self.codegen_expression(v.value);
                try self.stack_map.put(v.name, arr);
                return arr;
            },
            else => {
                const alloca = try self.codegen_alloca_const(v);
                const e = try self.codegen_expression(v.value);
                // store value on stack space
                _ = llvm.LLVMBuildStore(self.builder, e, alloca);
                try self.stack_map.put(v.name, alloca);
                return e;
            },
        }
    }

    pub fn codegen_alloca_var(self: *Codegen, v: *ast.VarStmt) !llvm.LLVMValueRef {
        const t = if (v.type_ann) |ann| try self.get_type(ann) else try self.get_llvm_type_of(self.expr_type(v.value));
        const name = try self.allocator.dupeZ(u8, v.name);
        defer self.allocator.free(name);
        return llvm.LLVMBuildAlloca(self.builder, t, name);
    }

    pub fn codegen_alloca_const(self: *Codegen, v: *ast.ConstStmt) !llvm.LLVMValueRef {
        const t = if (v.type_ann) |ann| try self.get_type(ann) else try self.get_llvm_type_of(self.expr_type(v.value));
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
        return llvm.LLVMBuildRetVoid(self.builder);
    }

    pub fn codegen_expression_statement(self: *Codegen, e_stmt: *ast.ExprStmt) !llvm.LLVMValueRef {
        if (e_stmt.value) |e| {
            return try self.codegen_expression(e);
        }
        unreachable;
    }

    pub fn codegen_expression(self: *Codegen, e: *ast.Expr) !llvm.LLVMValueRef {
        return switch (e.*) {
            .literal => |*l| self.codegen_literal(l, e),
            .binary => |*b| self.codegen_binary(b),
            .unary => |*u| self.codegen_unary(u),
            .call => |*c| self.codegen_call(c),
            .ident => |*i| self.codegen_ident(i),
            .array_literal => |*a| try self.codegen_array(a, e),
            .index => |*i| try self.codegen_index(i),
            else => unreachable,
        };
    }

    pub fn codegen_index(self: *Codegen, i: *ast.IndexExpr) anyerror!llvm.LLVMValueRef {
        // Currently only support one-dimensional arrays.
        if (i.args.items.len != 1) {
            return error.InvalidIndex;
        }

        const arr = switch (i.target.*) {
            .ident => |ident| self.stack_map.get(ident.name) orelse return error.UnknownVariable,

            else => try self.codegen_expression(i.target),
        };
        // Generate the index expression.
        const index = try self.codegen_expression(i.args.items[0]);
        const array_ty = try self.get_llvm_type_of(self.expr_type(i.target));
        var indices = [2]llvm.LLVMValueRef{
            llvm.LLVMConstInt(llvm.LLVMInt64Type(), 0, 0),
            index,
        };

        const element_ptr = llvm.LLVMBuildGEPWithNoWrapFlags(
            self.builder,
            array_ty,
            arr,
            &indices,
            2,
            "",
            0,
        );

        const element_ty = llvm.LLVMGetElementType(array_ty);
        const ld = llvm.LLVMBuildLoad2(self.builder, element_ty, element_ptr, "");

        return ld;
    }

    pub fn codegen_array_element_ptr(self: *Codegen, i: *ast.IndexExpr) !llvm.LLVMValueRef {
        if (i.args.items.len != 1) {
            return error.InvalidArrayIndex;
        }

        // For now, array target must be an identifier.
        const arr = switch (i.target.*) {
            .ident => |ident| self.stack_map.get(ident.name) orelse {
                return error.UnknownVariable;
            },
            else => return error.UnsupportedArrayTarget,
        };

        const array_ty = llvm.LLVMGetAllocatedType(arr);
        const index = try self.codegen_expression(i.args.items[0]);
        var indices = [2]llvm.LLVMValueRef{
            llvm.LLVMConstInt(llvm.LLVMInt64Type(), 0, 0),
            index,
        };

        return llvm.LLVMBuildGEPWithNoWrapFlags(
            self.builder,
            array_ty,
            arr,
            &indices,
            2,
            "",
            0,
        );
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

        // note: commenting this out, as these checks should be
        // handled in sema, not in codegen, right?

        // const expected = llvm.LLVMCountParamTypes(func_type);
        // if (expected != n_args) {
        //     std.debug.print("expected args = {}, actual args = {}\n", .{ expected, n_args });
        // }

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

    pub fn codegen_literal(self: *Codegen, l: *ast.LiteralExpr, e: *ast.Expr) !llvm.LLVMValueRef {
        const ty = self.expr_type(e);

        switch (l.kind) {
            .integer => {
                const i = try std.fmt.parseInt(c_ulonglong, l.raw, 10);
                return llvm.LLVMConstInt(try self.get_llvm_type_of(ty), i, 1);
            },
            .float => {
                const f = try std.fmt.parseFloat(f64, l.raw);
                return llvm.LLVMConstReal(try self.get_llvm_type_of(ty), f);
            },
            .bool_true => return llvm.LLVMConstInt(llvm.LLVMInt1Type(), 1, 0),
            .bool_false => return llvm.LLVMConstInt(llvm.LLVMInt1Type(), 0, 0),
            .char => return llvm.LLVMConstInt(llvm.LLVMInt8Type(), l.raw[0], 0),
            .string => {
                const name = try self.allocator.dupeZ(u8, l.raw);
                defer self.allocator.free(name);
                // TODO: maintain the global string table
                return llvm.LLVMBuildGlobalString(self.builder, name, ".str0");
            },
        }
    }

    fn llvm_int_type_of(self: *Codegen, ty: types.TypeId) !llvm.LLVMTypeRef {
        if (ty == .invalid) return llvm.LLVMInt32Type();

        return switch (self.compiler.sema.types.get(ty).*) {
            .primitive => |p| switch (p) {
                .i8, .u8 => llvm.LLVMInt8Type(),
                .i16, .u16 => llvm.LLVMInt16Type(),
                .i32, .u32 => llvm.LLVMInt32Type(),
                .i64, .u64, .usize, .isize => llvm.LLVMInt64Type(),
                else => llvm.LLVMInt32Type(),
            },
            else => llvm.LLVMInt32Type(),
        };
    }

    fn llvm_float_type_of(self: *Codegen, ty: types.TypeId) !llvm.LLVMTypeRef {
        if (ty == .invalid) return llvm.LLVMInt32Type();

        return switch (self.compiler.sema.types.get(ty).*) {
            .primitive => |p| switch (p) {
                .f32 => llvm.LLVMFloatType(),
                .f64 => llvm.LLVMDoubleType(),
                else => llvm.LLVMDoubleType(),
            },
            else => llvm.LLVMDoubleType(),
        };
    }

    fn codegen_compound_op(self: *Codegen, op: ast.CompoundOp, l: llvm.LLVMValueRef, r: llvm.LLVMValueRef, is_signed: bool) !llvm.LLVMValueRef {
        const l_ty = llvm.LLVMTypeOf(l);
        const type_kind = llvm.LLVMGetTypeKind(l_ty);
        const is_float =
            type_kind == llvm.LLVMFloatTypeKind or
            type_kind == llvm.LLVMDoubleTypeKind;

        return switch (op) {
            .add => if (is_float) llvm.LLVMBuildFAdd(self.builder, l, r, "add_compound") else llvm.LLVMBuildAdd(self.builder, l, r, "add_compound"),
            .sub => if (is_float) llvm.LLVMBuildFSub(self.builder, l, r, "sub_compound") else llvm.LLVMBuildSub(self.builder, l, r, "sub_compound"),
            .mul => if (is_float) llvm.LLVMBuildFMul(self.builder, l, r, "mul_compound") else llvm.LLVMBuildMul(self.builder, l, r, "mul_compound"),
            .div => if (is_float) llvm.LLVMBuildFDiv(self.builder, l, r, "div_compound") else if (is_signed) llvm.LLVMBuildSDiv(self.builder, l, r, "div_compound") else llvm.LLVMBuildUDiv(self.builder, l, r, "div_compound"),
            .mod => if (is_float) llvm.LLVMBuildFRem(self.builder, l, r, "mod_compound") else if (is_signed) llvm.LLVMBuildSRem(self.builder, l, r, "mod_compound") else llvm.LLVMBuildURem(self.builder, l, r, "mod_compound"),
            .bit_or => llvm.LLVMBuildOr(self.builder, l, r, "log_compound"),
            .bit_xor => llvm.LLVMBuildXor(self.builder, l, r, "log_compound"),
            .bit_and => llvm.LLVMBuildAnd(self.builder, l, r, "log_compound"),
            .shl => llvm.LLVMBuildShl(self.builder, l, r, "shift_compound"),
            .shr => llvm.LLVMBuildLShr(self.builder, l, r, "shift_compound"),
        };
    }

    pub fn codegen_binary(self: *Codegen, b: *ast.BinaryExpr) anyerror!llvm.LLVMValueRef {
        const l = try self.codegen_expression(b.lhs);
        const r = try self.codegen_expression(b.rhs);
        const lty = self.expr_type(b.lhs);
        const is_float = switch (self.compiler.sema.types.get(lty).*) {
            .primitive => |p| p == .f32 or p == .f64,
            else => false,
        };
        const is_signed = switch (self.compiler.sema.types.get(lty).*) {
            .primitive => |p| switch (p) {
                .i8, .i16, .i32, .i64, .isize => true,
                else => false,
            },
            else => false,
        };
        // TODO: handle overflow and underflow
        return switch (b.op) {
            .add => if (is_float) llvm.LLVMBuildFAdd(self.builder, l, r, "add_bin") else llvm.LLVMBuildAdd(self.builder, l, r, "add_bin"),
            .sub => if (is_float) llvm.LLVMBuildFSub(self.builder, l, r, "sub_bin") else llvm.LLVMBuildSub(self.builder, l, r, "sub_bin"),
            .mul => if (is_float) llvm.LLVMBuildFMul(self.builder, l, r, "mul_bin") else llvm.LLVMBuildMul(self.builder, l, r, "mul_bin"),
            .div => if (is_float) llvm.LLVMBuildFDiv(self.builder, l, r, "div_bin") else if (is_signed) llvm.LLVMBuildSDiv(self.builder, l, r, "div_bin") else llvm.LLVMBuildUDiv(self.builder, l, r, "div_bin"),
            .mod => if (is_float) llvm.LLVMBuildFRem(self.builder, l, r, "mod_bin") else if (is_signed) llvm.LLVMBuildSRem(self.builder, l, r, "mod_bin") else llvm.LLVMBuildURem(self.builder, l, r, "mod_bin"),
            .eq => if (is_float) llvm.LLVMBuildFCmp(self.builder, llvm.LLVMRealOEQ, l, r, "cmp_bin") else llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntEQ, l, r, "cmp_bin"),
            .ne => if (is_float) llvm.LLVMBuildFCmp(self.builder, llvm.LLVMRealONE, l, r, "cmp_bin") else llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntNE, l, r, "cmp_bin"),
            .lt => if (is_float) llvm.LLVMBuildFCmp(self.builder, llvm.LLVMRealOLT, l, r, "cmp_bin") else llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntULT, l, r, "cmp_bin"),
            .gt => if (is_float) llvm.LLVMBuildFCmp(self.builder, llvm.LLVMRealOGT, l, r, "cmp_bin") else llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntUGT, l, r, "cmp_bin"),
            .le => if (is_float) llvm.LLVMBuildFCmp(self.builder, llvm.LLVMRealOLE, l, r, "cmp_bin") else llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntULE, l, r, "cmp_bin"),
            .ge => if (is_float) llvm.LLVMBuildFCmp(self.builder, llvm.LLVMRealOGE, l, r, "cmp_bin") else llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntUGE, l, r, "cmp_bin"),
            .bit_or => llvm.LLVMBuildOr(self.builder, l, r, "log_bin"),
            .bit_xor => llvm.LLVMBuildXor(self.builder, l, r, "log_bin"),
            .bit_and => llvm.LLVMBuildAnd(self.builder, l, r, "log_bin"),
            .logical_or => llvm.LLVMBuildOr(self.builder, l, r, "or_bin"),
            .logical_and => llvm.LLVMBuildAnd(self.builder, l, r, "and_bin"),
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
        const oty = self.expr_type(u.operand);
        const is_float = switch (self.compiler.sema.types.get(oty).*) {
            .primitive => |p| p == .f32 or p == .f64,
            else => false,
        };
        return switch (u.op) {
            .neg => if (is_float) llvm.LLVMBuildFNeg(self.builder, e, "neg_un") else llvm.LLVMBuildNeg(self.builder, e, "neg_un"),
            .bit_not => llvm.LLVMBuildNot(self.builder, e, "bit_not_un"),
            .addr_of => switch (u.operand.*) {
                .ident => |*i| self.stack_map.get(i.name).?,
                else => unreachable,
            },
            .not => llvm.LLVMBuildNot(self.builder, e, "not_un"),
            else => {
                // TODO:
                unreachable;
            },
        };
    }

    pub fn get_type(self: *Codegen, ret_type: *ast.Type) anyerror!llvm.LLVMTypeRef {
        // TODO: handle optionals and errors
        switch (ret_type.base) {
            .primitive => |*p| return self.get_primitive_type(p),
            .pointer => |p| return llvm.LLVMPointerType(try self.get_type(p), 0),
            .array => |*a| {
                const ele_ty = try self.get_type(a.elem);
                const sz = switch (a.size) {
                    .fixed => |s| try std.fmt.parseInt(c_uint, s, 10),
                    else => {
                        unreachable;
                    },
                };
                return llvm.LLVMArrayType(ele_ty, sz);
            },
            else => {
                // TODO:
                unreachable;
            },
        }
    }

    pub fn get_primitive_type(self: *Codegen, p: *ast.PrimitiveType) !llvm.LLVMTypeRef {
        _ = self;
        switch (p.*) {
            .i8, .u8 => return llvm.LLVMInt8Type(),
            .i16, .u16 => return llvm.LLVMInt16Type(),
            .i32, .u32 => return llvm.LLVMInt32Type(),
            .i64, .u64, .usize, .isize => return llvm.LLVMInt64Type(),
            .f32 => return llvm.LLVMFloatType(),
            .f64 => return llvm.LLVMDoubleType(),
            .bool => return llvm.LLVMInt1Type(),
            .char => return llvm.LLVMInt8Type(),
            .str => return llvm.LLVMPointerType(llvm.LLVMInt8Type(), 64),
        }
    }

    pub fn get_llvm_type_of(self: *Codegen, ty: types.TypeId) anyerror!llvm.LLVMTypeRef {
        if (ty == .invalid) return llvm.LLVMInt32Type(); // note: for temp if some types are not managed in sema for now

        return switch (self.compiler.sema.types.get(ty).*) {
            .primitive => |p| switch (p) {
                .i8, .u8 => return llvm.LLVMInt8Type(),
                .i16, .u16 => return llvm.LLVMInt16Type(),
                .i32, .u32 => return llvm.LLVMInt32Type(),
                .i64, .u64, .usize, .isize => return llvm.LLVMInt64Type(),
                .f32 => return llvm.LLVMFloatType(),
                .f64 => return llvm.LLVMDoubleType(),
                .bool => return llvm.LLVMInt1Type(),
                .char => return llvm.LLVMInt8Type(),
                .str => return llvm.LLVMPointerType(llvm.LLVMInt8Type(), 64),
            },
            .pointer => |p| llvm.LLVMPointerType(try self.get_llvm_type_of(p.child), 0),
            .array => |a| {
                const ele_ty = try self.get_llvm_type_of(a.child);
                const sz: c_uint = @intCast(a.len);
                return llvm.LLVMArrayType(ele_ty, sz);
            },
            else => {
                //todo: other typse
                unreachable;
            },
        };
    }

    fn expr_type(self: *Codegen, e: *ast.Expr) types.TypeId {
        return self.compiler.sema.expr_types.get(e) orelse .invalid;
    }
};
