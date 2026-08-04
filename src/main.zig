const std = @import("std");
const core = @import("Core.zig");

pub fn main() !void {
    const ctx: core.LLVMContextRef = core.LLVMContextCreate();
    const mod: core.LLVMModuleRef = core.LLVMModuleCreateWithNameInContext("module", ctx);
    const mod_str = core.LLVMPrintModuleToString(mod);
    std.debug.print("Ed is coming to rule the world bok! bok!.\n", .{});
    std.debug.print("{s}\n", .{mod_str});
}
