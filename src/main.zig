const std = @import("std");
const llvm = @import("llvm");

pub fn main() !void {
    const ctx: llvm.LLVMContextRef = llvm.LLVMContextCreate();
    const mod: llvm.LLVMModuleRef = llvm.LLVMModuleCreateWithNameInContext("module", ctx);
    const mod_str = llvm.LLVMPrintModuleToString(mod);
    std.debug.print("Ed is coming to rule the world bok! bok!.\n", .{});
    std.debug.print("{s}\n", .{mod_str});
}
