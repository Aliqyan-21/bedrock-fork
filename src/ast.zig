const std = @import("std");
const t = @import("token.zig");

pub const Item = struct {
    import_def: ImportDef,
    function: FunctionDef,
    struct_def: StructDef,
    enum_def: EnumDef,
    extern_def: ExternDef,
    global_var_def: GlobalVarDef,
    const_def: ConstDef,
};

pub const Program = struct {
    items: []Item,
};

// import_def = "import" IDENT {"." IDENT} ";"
pub const ImportDef = struct {};

// function = [ "pub" ] [ "inline" ] "func" IDENT [ type_params ] "(" [ params ] ")" result block "end"
pub const FunctionDef = struct {};

// struct_def = [ "pub" ] "type" IDENT [ type_params ] "=" "struct" [ struct_members ] "end"
pub const StructDef = struct {};

// enum_def = [ "pub" ] "type" IDENT [ type_params ] "=" "enum" [ enum_variants ] "end"
pub const EnumDef = struct {};

// extern_def = "extern" ( "func" IDENT "(" [ extern_params ] ")" "->" type
//            | "proc" IDENT "(" [ extern_params ] ")" )
pub const ExternDef = struct {};

// global_var_def  = [ "pub" ] "var" IDENT [ ":" ["?"] type ] "=" expression ";"
pub const GlobalVarDef = struct {};

// const_def = [ "pub" ] "const" IDENT [ ":" ["?"] type ] "=" expression ";"
pub const ConstDef = struct {};

pub const PrimitiveType = enum {
    i8,
    i16,
    i32,
    i64,
    u8,
    u16,
    u32,
    u64,
    usize,
    isize,
    f32,
    f64,
    bool,
    char,
    str,
};

// ast have it's own allocator and deinit
// and ofc it has internal arena, all nodes
// get freed in one shot by deinit, not individually freed
pub const AST = struct {
    arena: std.heap.ArenaAllocator,
    program: Program,

    pub fn init(n_allocator: std.mem.Allocator) AST {
        return .{
            .arena = std.heap.ArenaAllocator.init(n_allocator),
            .program = .{ .items = &.{} },
        };
    }

    pub fn allocator(self: *AST) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn deinit(self: *AST) void {
        self.arena.deinit();
    }
};
