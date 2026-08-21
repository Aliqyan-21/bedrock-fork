const std = @import("std");
const ast = @import("ast.zig");
const compiler = @import("compiler.zig");

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
            .function => {},
            .proc => {},
            .struct_def => {},
            .enum_def => {},
            .extern_def => {},
            .var_def => {},
            .const_def => {},
        }
    }

    // note: so the structure is that we visit these different definitions and all the things
    // like basically make visitors and check for our decided semantics...
    // so progressively we keep developing the semantics here.
};
