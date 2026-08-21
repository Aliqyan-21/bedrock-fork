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

    pub fn init(allocator: std.mem.Allocator, c: *compiler.Compiler) Codegen {
        return Codegen{
            .allocator = allocator,
            .compiler = c,
            .ctx = llvm.LLVMContextCreate(),
            .mod = undefined,
        };
    }

    pub fn codegen(self: *Codegen) ![*c]u8 {
        self.mod = llvm.LLVMModuleCreateWithNameInContext("module", self.ctx);
        try self.codegen_program(self.compiler.ast.program);
        const mod_str = llvm.LLVMPrintModuleToString(self.mod);
        return mod_str;
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
        const func_type: llvm.LLVMTypeRef = llvm.LLVMFunctionType(llvm.LLVMInt32Type(), null, 0, 0);
        const main_func: llvm.LLVMValueRef = llvm.LLVMAddFunction(self.mod, function.name.ptr, func_type);
        const entry: llvm.LLVMBasicBlockRef = llvm.LLVMAppendBasicBlock(main_func, "entry");
        _ = entry;
    }
};
