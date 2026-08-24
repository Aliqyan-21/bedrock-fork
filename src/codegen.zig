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

    pub fn init(allocator: std.mem.Allocator, c: *compiler.Compiler) Codegen {
        return Codegen{
            .allocator = allocator,
            .compiler = c,
            .ctx = llvm.LLVMContextCreate(),
            .mod = undefined,
            .builder = llvm.LLVMCreateBuilder(),
            .entry = undefined,
        };
    }

    pub fn codegen(self: *Codegen) !llvm.LLVMModuleRef {
        self.mod = llvm.LLVMModuleCreateWithNameInContext("module", self.ctx);
        try self.codegen_program(self.compiler.ast.program);
        return self.mod;
    }

    pub fn codegen_program(self: *Codegen, program: ast.Program) !void {
        try self.codegen_items(program.items);
    }

    pub fn codegen_items(self: *Codegen, items: std.ArrayList(ast.Item)) !void {
        for (items.items) |*item| {
            switch (item.*) {
                .function => |*f| try self.codegen_function(f),
                else => {
                    // TODO:
                },
            }
        }
    }

    pub fn codegen_function(self: *Codegen, function: *ast.FunctionDef) !void {
        const ret_type = try self.get_type(function.result);
        const params = try self.codegen_params(function.params);
        const params_len: c_uint = @intCast(function.params.items.len);
        const func_type: llvm.LLVMTypeRef = llvm.LLVMFunctionType(ret_type, @ptrCast(@constCast(params[0..function.params.items.len])), params_len, 0);
        const name = try self.allocator.dupeZ(u8, function.name);
        defer self.allocator.free(name);
        const main_func: llvm.LLVMValueRef = llvm.LLVMAddFunction(self.mod, name.ptr, func_type);

        // set function arg names
        for (function.params.items, 0..) |p, idx| {
            const arg = llvm.LLVMGetParam(main_func, @intCast(idx));
            llvm.LLVMSetValueName2(arg, @ptrCast(p.name), p.name.len);
        }

        self.entry = llvm.LLVMAppendBasicBlock(main_func, "entry");
        llvm.LLVMPositionBuilderAtEnd(self.builder, self.entry);
        try self.codegen_statements(function.body);
    }

    pub fn codegen_statements(self: *Codegen, stmts: std.ArrayList(ast.Stmt)) !void {
        for (stmts.items) |*stmt| {
            switch (stmt.*) {
                .return_stmt => |*r| try self.codegen_return(r),
                .expr_stmt => |*e| try self.codegen_expression_statement(e),
                else => {
                    // TODO:
                },
            }
        }
    }

    pub fn codegen_params(self: *Codegen, params: std.ArrayList(ast.Param)) ![1024]llvm.LLVMTypeRef {
        var p_types: [1024]llvm.LLVMTypeRef = undefined;
        for (params.items, 0..) |param, idx| {
            const t = try self.get_type(param.type);
            p_types[idx] = t;
        }

        return p_types;
    }

    pub fn codegen_return(self: *Codegen, r: *ast.ReturnStmt) !void {
        if (r.value) |e| {
            const val = try self.codegen_expression(e);
            _ = llvm.LLVMBuildRet(self.builder, val);
        }
    }

    pub fn codegen_expression_statement(self: *Codegen, e_stmt: *ast.ExprStmt) !void {
        if (e_stmt.value) |e| {
            _ = try self.codegen_expression(e);
        }
    }

    pub fn codegen_expression(self: *Codegen, e: *ast.Expr) !llvm.LLVMValueRef {
        return switch (e.*) {
            .literal => |*l| self.codegen_literal(l),
            .binary => |*b| self.codegen_binary(b),
            .unary => |*u| self.codegen_unary(u),
            else => unreachable,
        };
    }

    pub fn codegen_literal(self: *Codegen, l: *ast.LiteralExpr) !llvm.LLVMValueRef {
        _ = self;
        const i = try std.fmt.parseInt(c_ulonglong, l.raw, 10);
        return llvm.LLVMConstInt(llvm.LLVMInt32Type(), i, 1);
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
            .lt => llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntULE, l, r, "cmp_bin"),
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
            else => {
                // TODO:
                unreachable;
            },
        }
    }
};
