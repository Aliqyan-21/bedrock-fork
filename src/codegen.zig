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
        // NOTE: just handle the corpus/codegen/hello.bok for now
        const ret_type = self.get_func_ret_type(function.result);
        // TODO: check for params
        const func_type: llvm.LLVMTypeRef = llvm.LLVMFunctionType(ret_type, null, 0, 0);
        const name = try self.allocator.dupeZ(u8, function.name);
        defer self.allocator.free(name);
        const main_func: llvm.LLVMValueRef = llvm.LLVMAddFunction(self.mod, name.ptr, func_type);
        self.entry = llvm.LLVMAppendBasicBlock(main_func, "entry");
        llvm.LLVMPositionBuilderAtEnd(self.builder, self.entry);
        try self.codegen_statements(function.body);
    }

    pub fn codegen_statements(self: *Codegen, stmts: std.ArrayList(ast.Stmt)) !void {
        for (stmts.items) |*stmt| {
            switch (stmt.*) {
                .return_stmt => |*r| try self.codegen_return(r),
                else => {
                    // TODO:
                },
            }
        }
    }

    pub fn codegen_return(self: *Codegen, r: *ast.ReturnStmt) !void {
        if (r.value) |e| {
            switch (e.*) {
                .literal => |*l| try self.codegen_literal(l),
                else => {
                    // TODO:
                },
            }
        }
    }

    pub fn codegen_literal(self: *Codegen, l: *ast.LiteralExpr) !void {
        const i = try std.fmt.parseInt(c_ulonglong, l.raw, 10);
        const i_c: llvm.LLVMValueRef = llvm.LLVMConstInt(llvm.LLVMInt32Type(), i, 1);
        _ = llvm.LLVMBuildRet(self.builder, i_c);
    }

    pub fn get_func_ret_type(self: *Codegen, ret_type: *ast.Type) llvm.LLVMTypeRef {
        // TODO: handle optionals and errors
        switch (ret_type.base) {
            .primitive => |*p| return self.get_primitive_type(p),
            else => {
                // TODO:
                unreachable;
            },
        }
    }

    pub fn get_primitive_type(self: *Codegen, p: *ast.PrimitiveType) llvm.LLVMTypeRef {
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
