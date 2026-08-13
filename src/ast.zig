const std = @import("std");
const Token = @import("token.zig").Token;

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
pub const ImportDef = struct {
    path: [][]const u8,
    token: Token,
};

// type_param = IDENT
pub const TypeParam = struct {
    name: []const u8,
    token: Token,
};

// param = IDENT ":" ["?"] ["const"] type
pub const Param = struct {
    name: []const u8,
    is_optional: bool,
    is_const: bool,
    type: *Type,
    token: Token,
};

// result = "->" ( "?" type | type "!" | type )
pub const Result = union(enum) {
    plain: *Type,
    optional: *Type, // "?"
    error_union: *Type, // "!"
};

// function = [ "pub" ] [ "inline" ] "func" IDENT [ type_params ] "(" [ params ] ")" result block "end"
pub const FunctionDef = struct {
    is_pub: bool,
    is_inline: bool,
    name: []const u8,
    type_params: []TypeParam,
    params: []Param,
    result: Result,
    body: []Stmt,
    token: Token,
};

pub const ProcDef = struct {
    is_pub: bool,
    is_inline: bool,
    name: []const u8,
    type_params: []TypeParam,
    params: []Param,
    body: []Stmt,
    token: Token,
};

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

// type = "i8" | "i16" | "i32" | "i64" //
//      | "u8" | "u16" | "u32" | "u64" //
//      | "usize" | "isize"            //
//      | "f32" | "f64"                //
//      | "bool" | "char" | "str"      //
//      | "*" type                     //
//      | array_type                   //
//      | named_type                   //
//      | func_type                    //
//      | proc_type                    //

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

pub const ArraySize = struct {};

// array_type = "[" ( INTEGER | "_" ) "]" type
pub const ArrayType = struct {
    size: ArraySize,
    elem: *Type,
    token: Token,
};

// named_type = IDENT [ "[" type { "," type } [ "," ] "]" ]
pub const NamedType = struct {
    name: []const u8,
    args: []*Type,
    token: Token,
};

// func_type  = "func" "(" [ type_list ] ")" result
pub const FuncType = struct {
    params: []*Type,
    result: Result,
    token: Token,
};

// proc_type  = "proc" "(" [ type_list ] ")"
pub const ProcType = struct {
    params: []*Type,
    token: Token,
};

pub const Type = struct {
    primitive: PrimitiveType,
    pointer: *Type,
    array: ArrayType,
    named: NamedType,
    func: FuncType,
    proc: ProcType,
};

pub const Stmt = struct {};

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
