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

pub const TypeAnn = struct {
    is_optional: bool,
    type: *Type,
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

pub const ArraySize = union(enum) {
    fixed: []const u8, // INTEGER
    inferred, // "_"
};

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

pub const Type = union(enum) {
    primitive: PrimitiveType,
    pointer: *Type,
    array: ArrayType,
    named: NamedType,
    func: FuncType,
    proc: ProcType,
};

pub const LiteralKind = enum {
    integer,
    float,
    char,
    string,
    bool_true,
    bool_false,
};

pub const LiteralExpr = struct {
    kind: LiteralKind,
    raw: []const u8,
    token: Token,
};

pub const IdentExpr = struct {
    name: []const u8,
    token: Token,
};

pub const UnaryOp = enum {
    neg,
    not,
    bit_not,
    addr_of,
    deref,
};

pub const BinaryOp = enum {
    orelse_op,
    logical_or,
    logical_and,
    eq,
    ne,
    lt,
    gt,
    le,
    ge,
    bit_or,
    bit_xor,
    bit_and,
    shl,
    shr,
    range,
    add,
    sub,
    mul,
    div,
    mod,
};

pub const BinaryExpr = struct {
    op: BinaryOp,
    lhs: *Expr,
    rhs: *Expr,
    token: Token,
};

pub const UnaryExpr = struct {
    op: UnaryOp,
    operand: *Expr,
    token: Token,
};

// A "." Ident
pub const FieldAccessExpr = struct {
    target: *Expr,
    field: []const u8,
    token: Token,
};

pub const CallArg = struct {
    name: ?[]const u8,
    value: *Expr,
};

pub const CallExpr = struct {
    callee: *Expr,
    args: []CallArg,
    token: Token,
};

pub const IndexExpr = struct {};
pub const OptionalUnwrapExpr = struct {};
pub const ArrayLiteralExpr = struct {};
pub const IfExpr = struct {};
pub const MatchExpr = struct {};
pub const WhileExpr = struct {};
pub const ForExpr = struct {};
pub const ComptimeExpr = struct {};

pub const Expr = union(enum) {
    literal: LiteralExpr,
    ident: IdentExpr,
    binary: BinaryExpr,
    unary: UnaryExpr,
    field_access: FieldAccessExpr,
    call: CallExpr,
    index: IndexExpr,
    optional_unwrap: OptionalUnwrapExpr,
    array_literal: ArrayLiteralExpr,
    if_expr: IfExpr,
    match_expr: MatchExpr,
    while_expr: WhileExpr,
    for_expr: ForExpr,
    comptime_expr: ComptimeExpr,
};

// statement       = var_stmt | const_stmt | local_static_var_stmt | assign_stmt | defer_stmt
//                 | unsafe_stmt | control_flow_stmt | return_stmt | expr_stmt
pub const Stmt = union(enum) {
    var_stmt: VarStmt,
    const_stmt: ConstStmt,
    assign_stmt: AssignStmt,
    local_static_var_stmt: LocalStaticVarStmt,
    defer_stmt: DeferStmt,
    unsafe_stmt: UnsafeStmt,
    control_flow_stmt: *Expr,
    return_stmt: ReturnStmt,
    expr_stmt: ExprStmt,
};

// var_stmt = "var" IDENT [ ":" ["?"] type ] "=" expression ";"
pub const VarStmt = struct {
    name: []const u8,
    type_ann: ?TypeAnn,
    value: *Expr,
    token: Token,
};

// const_stmt = "const" IDENT [ ":" ["?"] type ] "=" expression ";"
pub const ConstStmt = struct {
    name: []const u8,
    type_ann: ?TypeAnn,
    value: *Expr,
    token: Token,
};

// local_static_var_stmt = "static" "var" IDENT [ ":" ["?"] type ] "=" expression ";"
pub const LocalStaticVarStmt = struct {
    name: []const u8,
    type_ann: ?TypeAnn,
    value: *Expr,
    token: Token,
};

pub const CompoundOp = enum {
    add,
    sub,
    mul,
    div,
    mod,
    bit_and,
    bit_or,
    bit_xor,
    shl,
    shr,
};

// assign_stmt = place_expr ( "=" | compound_op ) expression ";"
pub const AssignStmt = struct {
    target: *Expr,
    op: ?CompoundOp, // if null -> simple '='
    value: *Expr,
    token: Token,
};

// defer_stmt = "defer" ( var_stmt | const_stmt | assign_stmt | control_flow_stmt | return_stmt | expr_stmt )
pub const DeferrableStmt = union(enum) {
    var_stmt: VarStmt,
    const_stmt: ConstStmt,
    assign_stmt: AssignStmt,
    control_flow_stmt: *Expr,
    return_stmt: ReturnStmt,
    expr_stmt: ExprStmt,
};

pub const DeferStmt = struct {
    inner: *DeferrableStmt,
    token: Token,
};

// unsafe_stmt = "unsafe" block "end"
pub const UnsafeStmt = struct {
    body: []Stmt,
    token: Token,
};

// return_stmt = return_expr ";"
pub const ReturnStmt = struct {
    value: ?*Expr,
    token: Token,
};

// expr_stmt = expression ";"
pub const ExprStmt = struct {
    value: ?*Expr,
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
