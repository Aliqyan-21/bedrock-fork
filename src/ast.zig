const std = @import("std");
const Token = @import("token.zig").Token;

pub const Item = union(enum) {
    import_def: ImportDef,
    function: FunctionDef,
    proc: ProcDef,
    struct_def: StructDef,
    enum_def: EnumDef,
    extern_def: ExternDef,
    var_def: VarDef,
    const_def: ConstDef,

    pub fn print(self: *Item, indent: usize) anyerror!void {
        switch (self.*) {
            .import_def => |*i| try i.print(indent),
            .function => |*f| try f.print(indent),
            .proc => |*p| try p.print(indent),
            .struct_def => |*s| try s.print(indent),
            .enum_def => |*e| try e.print(indent),
            .extern_def => |*e| try e.print(indent),
            .var_def => |*v| try v.print(indent),
            .const_def => |*c| try c.print(indent),
        }
    }
};

pub const Program = struct {
    items: std.ArrayList(Item),
};

// import_def = "import" IDENT {"." IDENT} ";"
pub const ImportDef = struct {
    path: [][]const u8,
    token: Token,

    pub fn print(self: *ImportDef, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("import ", .{});
        for (0..self.path.len) |i| {
            const p = self.path[i];
            std.debug.print("{s}", .{p});
            if (i + 1 < self.path.len) {
                std.debug.print(".", .{});
            }
        }
        std.debug.print("\n", .{});
    }
};

// type_param = IDENT
pub const TypeParam = struct {
    name: []const u8,
    token: Token,

    pub fn print(self: *TypeParam, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("type param: {s}\n", .{self.name});
    }
};

// param = IDENT ":" ["?"] ["const"] type
pub const Param = struct {
    name: []const u8,
    is_optional: bool,
    is_const: bool,
    type: *Type,
    token: Token,

    pub fn print(self: *Param, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("param: {s} -> ", .{self.name});
        try self.type.*.print(0);
    }
};

// result = "->" ( "?" type | type "!" | type )
pub const Result = union(enum) {
    plain: *Type,
    optional: *Type, // "?"
    error_union: *Type, // "!"

    pub fn print(self: *Result, indent: usize) anyerror!void {
        switch (self.*) {
            .plain => |t| try t.print(indent),
            .optional => |t| {
                std.debug.print("optional\n", .{});
                try t.print(indent + 4);
            },
            .error_union => |t| {
                std.debug.print("error union\n", .{});
                try t.print(indent + 4);
            },
        }
    }
};

pub const TypeAnn = struct {
    is_optional: bool,
    type: *Type,

    pub fn print(self: *TypeAnn, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        if (self.is_optional) {
            std.debug.print("optional type\n", .{});
        }
        try self.type.print(indent + 4);
    }
};

// function = [ "pub" ] [ "inline" ] "func" IDENT [ type_params ] "(" [ params ] ")" result block "end"
pub const FunctionDef = struct {
    is_pub: bool,
    is_inline: bool,
    name: []const u8,
    type_params: []TypeParam,
    params: std.ArrayList(Param),
    result: Result,
    body: std.ArrayList(Stmt),
    token: Token,

    pub fn print(self: *FunctionDef, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("function: {s}\n", .{self.name});
        for (self.type_params) |*tp| try tp.print(indent + 4);
        for (self.params.items) |*p| try p.print(indent + 4);
        try self.result.print(indent + 4);
        for (self.body.items) |*stmt| {
            for (0..indent + 4) |_| std.debug.print(" ", .{});
            std.debug.print("stmt\n", .{});
            try stmt.print(indent + 4);
        }
    }
};

pub const ProcDef = struct {
    is_pub: bool,
    is_inline: bool,
    name: []const u8,
    type_params: []TypeParam,
    params: []Param,
    body: []Stmt,
    token: Token,

    pub fn print(self: *ProcDef, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("proc: {s}\n", .{self.name});
        for (self.type_params) |*tp| try tp.print(indent + 4);
        for (self.params) |*p| try p.print(indent + 4);
        for (self.body) |*stmt| {
            for (0..indent + 4) |_| std.debug.print(" ", .{});
            std.debug.print("stmt\n", .{});
            try stmt.print(indent + 4);
        }
    }
};

// struct_def = [ "pub" ] "type" IDENT [ type_params ] "=" "struct" [ struct_members ] "end"
pub const StructDef = struct {
    is_pub: bool,
    name: []const u8,
    type_params: []TypeParam,
    fields: []StructField,
    methods: []MethodDef,
    token: Token,

    pub fn print(self: *StructDef, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("struct: {s}\n", .{self.name});
        for (self.type_params) |*tp| try tp.print(indent + 4);
        for (self.fields) |*f| try f.print(indent + 4);
        for (self.methods) |*m| try m.print(indent + 4);
    }
};

// enum_variants   = enum_variant { "," enum_variant } [ "," ]
// enum_variant    = IDENT
pub const EnumVariant = struct {
    name: []const u8,
    token: Token,

    pub fn print(self: *EnumVariant, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("enum variant: {s}\n", .{self.name});
    }
};

// enum_def = [ "pub" ] "type" IDENT [ type_params ] "=" "enum" [ enum_variants ] "end"
pub const EnumDef = struct {
    is_pub: bool,
    name: []const u8,
    type_params: []TypeParam,
    variants: []EnumVariant,
    token: Token,

    pub fn print(self: *EnumDef, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("enum: {s}\n", .{self.name});
        for (self.type_params) |*tp| try tp.print(indent + 4);
        for (self.variants) |*v| try v.print(indent + 4);
    }
};

// extern_params   = extern_param { "," extern_param } [ "," "..." ] | "..."
// extern_param    = IDENT ":" type
pub const ExternParam = struct {
    name: []const u8,
    type: *Type,
    token: Token,

    pub fn print(self: *ExternParam, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("extern param: {s}\n", .{self.name});
    }
};

// extern_def = "extern" ( "func" IDENT "(" [ extern_params ] ")" "->" type
//            | "proc" IDENT "(" [ extern_params ] ")" )
pub const ExternDef = struct {
    kind: union(enum) {
        func: struct {
            name: []const u8,
            params: []ExternParam,
            is_variadic: bool,
            result: *Type,
        },
        proc: struct {
            name: []const u8,
            params: []ExternParam,
            is_variadic: bool,
        },
    },
    token: Token,

    pub fn print(self: *ExternDef, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        switch (self.kind) {
            .func => |f| {
                std.debug.print("extern func: {s}\n", .{f.name});
                for (f.params) |*p| try p.print(indent + 4);
                try f.result.print(indent + 4);
            },
            .proc => |p| {
                std.debug.print("extern proc: {s}\n", .{p.name});
                for (p.params) |*param| try param.print(indent + 4);
            },
        }
    }
};

// var_def  = [ "pub" ] "var" IDENT [ ":" ["?"] type ] "=" expression ";"
pub const VarDef = struct {
    is_pub: bool,
    is_global: bool,
    name: []const u8,
    type_ann: ?TypeAnn,
    value: *Expr,
    token: Token,

    pub fn print(self: *VarDef, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("var: {s}\n", .{self.name});
    }
};

// const_def = [ "pub" ] "const" IDENT [ ":" ["?"] type ] "=" expression ";"
pub const ConstDef = struct {
    is_pub: bool,
    is_global: bool,
    name: []const u8,
    type_ann: ?TypeAnn,
    value: *Expr,
    token: Token,

    pub fn print(self: *ConstDef, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("const: {s}\n", .{self.name});
    }
};

// struct_field = ["pub"] IDENT ":" ["?"] type
pub const StructField = struct {
    is_pub: bool,
    name: []const u8,
    is_optional: bool,
    type: *Type,
    token: Token,

    pub fn print(self: *StructField, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("struct field: {s}\n", .{self.name});
    }
};

// method_def = [ "pub" ] [ "inline" ] "func" IDENT [ type_params ] "(" [ params ] ")" result block "end"
//            | [ "pub" ] [ "inline" ] "proc" IDENT [ type_params ] "(" [ params ] ")" block "end"
pub const MethodDef = union(enum) {
    func: FunctionDef,
    proc: ProcDef,

    pub fn print(self: *MethodDef, indent: usize) anyerror!void {
        switch (self.*) {
            .func => |*f| try f.print(indent),
            .proc => |*p| try p.print(indent),
        }
    }
};

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

    pub fn print(self: *PrimitiveType, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("primitive type: {s}\n", .{@tagName(self.*)});
    }
};

pub const ArraySize = union(enum) {
    fixed: []const u8, // INTEGER
    inferred, // "_"

    pub fn print(self: *ArraySize, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        switch (self.*) {
            .fixed => |s| std.debug.print("array size: {s}\n", .{s}),
            .inferred => std.debug.print("array size: inferred\n", .{}),
        }
    }
};

// array_type = "[" ( INTEGER | "_" ) "]" type
pub const ArrayType = struct {
    size: ArraySize,
    elem: *Type,
    token: Token,

    pub fn print(self: *ArrayType, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("array type\n", .{});
        try self.size.print(indent + 4);
        try self.elem.print(indent + 4);
    }
};

// named_type = IDENT [ "[" type { "," type } [ "," ] "]" ]
pub const NamedType = struct {
    name: []const u8,
    args: []*Type,
    token: Token,

    pub fn print(self: *NamedType, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("named type: {s}\n", .{self.name});
        for (self.args) |arg| try arg.print(indent + 4);
    }
};

// func_type  = "func" "(" [ type_list ] ")" result
pub const FuncType = struct {
    params: []*Type,
    result: Result,
    token: Token,

    pub fn print(self: *FuncType, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("func type\n", .{});
        std.debug.print("params:\n", .{});
        for (self.params) |param| try param.print(indent + 4);
        std.debug.print("result:\n", .{});
        try self.result.print(indent + 4);
    }
};

// proc_type  = "proc" "(" [ type_list ] ")"
pub const ProcType = struct {
    params: []*Type,
    token: Token,

    pub fn print(self: *ProcType, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("proc type\n", .{});
        for (self.params) |param| try param.print(indent + 4);
    }
};

pub const Type = union(enum) {
    primitive: PrimitiveType,
    pointer: *Type,
    array: ArrayType,
    named: NamedType,
    func: FuncType,
    proc: ProcType,

    pub fn print(self: *Type, indent: usize) anyerror!void {
        switch (self.*) {
            .primitive => |*p| try p.print(indent),
            .pointer => |p| {
                for (0..indent) |_| std.debug.print(" ", .{});
                std.debug.print("pointer type\n", .{});
                try p.print(indent + 4);
            },
            .array => |*a| try a.print(indent),
            .named => |*n| try n.print(indent),
            .func => |*f| try f.print(indent),
            .proc => |*p| try p.print(indent),
        }
    }
};

// Expressions //

pub const LiteralKind = enum {
    integer,
    float,
    char,
    string,
    bool_true,
    bool_false,

    pub fn print(self: *LiteralKind, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("literal kind: {s}\n", .{@tagName(self.*)});
    }
};

pub const LiteralExpr = struct {
    kind: LiteralKind,
    raw: []const u8,
    token: Token,

    pub fn print(self: *LiteralExpr, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("literal: {s}\n", .{self.raw});
        try self.kind.print(indent + 4);
    }
};

pub const IdentExpr = struct {
    name: []const u8,
    token: Token,

    pub fn print(self: *IdentExpr, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("identifier: {s}\n", .{self.name});
    }
};

pub const UnaryOp = enum {
    neg,
    not,
    bit_not,
    addr_of,
    deref,

    pub fn print(self: *UnaryOp, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("unary op: {s}\n", .{@tagName(self.*)});
    }
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

    pub fn print(self: *BinaryOp, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("binary op: {s}\n", .{@tagName(self.*)});
    }
};

pub const BinaryExpr = struct {
    op: BinaryOp,
    lhs: *Expr,
    rhs: *Expr,
    token: Token,

    pub fn print(self: *BinaryExpr, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("binary expr\n", .{});
        try self.op.print(indent + 4);
        try self.lhs.print(indent + 4);
        try self.rhs.print(indent + 4);
    }
};

pub const UnaryExpr = struct {
    op: UnaryOp,
    operand: *Expr,
    token: Token,

    pub fn print(self: *UnaryExpr, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("unary expr\n", .{});
        try self.op.print(indent + 4);
        try self.operand.print(indent + 4);
    }
};

// A "." Ident
pub const FieldAccessExpr = struct {
    target: *Expr,
    field: []const u8,
    token: Token,

    pub fn print(self: *FieldAccessExpr, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("field access: {s}\n", .{self.field});
        try self.target.print(indent + 4);
    }
};

pub const CallArg = struct {
    name: ?[]const u8,
    value: *Expr,

    pub fn print(self: *CallArg, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        if (self.name) |n| {
            std.debug.print("call arg: {s}\n", .{n});
        } else {
            std.debug.print("call arg\n", .{});
        }
        try self.value.print(indent + 4);
    }
};

pub const CallExpr = struct {
    callee: *Expr,
    args: []CallArg,
    token: Token,

    pub fn print(self: *CallExpr, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("call expr\n", .{});
        try self.callee.print(indent + 4);
        for (self.args) |*arg| try arg.print(indent + 4);
    }
};

// this support both, arr[i] and also
// foo[Type] -> generic instantiations
pub const IndexExpr = struct {
    target: *Expr,
    args: []*Expr,
    token: Token,

    pub fn print(self: *IndexExpr, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("index expr\n", .{});
        try self.target.print(indent + 4);
        for (self.args) |arg| try arg.print(indent + 4);
    }
};

// ?
pub const OptionalUnwrapExpr = struct {
    operand: *Expr,
    token: Token,

    pub fn print(self: *OptionalUnwrapExpr, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("optional unwrap expr\n", .{});
        try self.operand.print(indent + 4);
    }
};

// array_literal = "[" [ array_elems ] "]"
pub const ArrayLiteralExpr = struct {
    elements: []*Expr,
    token: Token,

    pub fn print(self: *ArrayLiteralExpr, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("array literal\n", .{});
        for (self.elements) |elem| try elem.print(indent + 4);
    }
};

// elif_clause = "elif" expression block
pub const ElifClause = struct {
    cond: *Expr,
    body: []Stmt,
    token: Token,

    pub fn print(self: *ElifClause, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("elif clause\n", .{});
        try self.cond.print(indent + 4);
        for (0..self.body.len) |i| {
            var stmt = self.body[i];
            for (0..indent + 4) |_| std.debug.print(" ", .{});
            std.debug.print("stmt\n", .{});
            try stmt.print(indent + 4);
        }
    }
};

// if_expr = "if" expression block { elif_clause } [ else_clause ] "end"
pub const IfExpr = struct {
    cond: *Expr,
    then_body: []Stmt,
    elifs: []ElifClause,
    else_body: ?[]Stmt,
    token: Token,

    pub fn print(self: *IfExpr, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("if expr\n", .{});
        try self.cond.print(indent + 4);
        for (0..self.then_body.len) |i| {
            var stmt = self.then_body[i];
            for (0..indent + 4) |_| std.debug.print(" ", .{});
            std.debug.print("stmt\n", .{});
            try stmt.print(indent + 4);
        }
        for (self.elifs) |*elif| try elif.print(indent + 4);
        if (self.else_body) |else_body| {
            for (0..indent + 4) |_| std.debug.print(" ", .{});
            std.debug.print("else clause\n", .{});
            for (0..else_body.len) |i| {
                var stmt = else_body[i];
                for (0..indent + 4) |_| std.debug.print(" ", .{});
                std.debug.print("stmt\n", .{});
                try stmt.print(indent + 6);
            }
        }
    }
};

// pattern = INTEGER | BOOL | IDENT
pub const Pattern = union(enum) {
    integer: []const u8,
    boolean: bool,
    ident: []const u8,

    pub fn print(self: *Pattern, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        switch (self.*) {
            .integer => |*i| std.debug.print("pattern integer: {s}\n", .{i.*}),
            .boolean => |*b| std.debug.print("pattern boolean: {}\n", .{b.*}),
            .ident => |*id| std.debug.print("pattern ident: {s}\n", .{id.*}),
        }
    }
};

// match_arm = "case" pattern block
pub const MatchArm = struct {
    pattern: Pattern,
    body: []Stmt,
    token: Token,

    pub fn print(self: *MatchArm, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("match arm\n", .{});
        try self.pattern.print(indent + 4);
        for (0..self.body.len) |i| {
            var stmt = self.body[i];
            for (0..indent + 4) |_| std.debug.print(" ", .{});
            std.debug.print("stmt\n", .{});
            try stmt.print(indent + 4);
        }
    }
};

// match_expr = "match" expression [ match_arms ] "end"
pub const MatchExpr = struct {
    subject: *Expr,
    arms: []MatchArm,
    else_body: ?[]Stmt,
    token: Token,

    pub fn print(self: *MatchExpr, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("match expr\n", .{});
        try self.subject.print(indent + 4);
        for (self.arms) |*arm| try arm.print(indent + 4);
        if (self.else_body) |*else_body| {
            for (0..indent + 4) |_| std.debug.print(" ", .{});
            std.debug.print("else clause\n", .{});
            for (0..else_body.len) |i| {
                var stmt = else_body.*[i];
                for (0..indent + 4) |_| std.debug.print(" ", .{});
                std.debug.print("stmt\n", .{});
                try stmt.print(indent + 6);
            }
        }
    }
};

// while_expr = "while" expression block "end"
pub const WhileExpr = struct {
    cond: *Expr,
    body: []Stmt,
    token: Token,

    pub fn print(self: *WhileExpr, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("while expr\n", .{});
        try self.cond.print(indent + 4);
        for (0..self.body.len) |i| {
            var stmt = self.body[i];
            for (0..indent + 4) |_| std.debug.print(" ", .{});
            std.debug.print("stmt\n", .{});
            try stmt.print(indent + 4);
        }
    }
};

// for_expr = "for" IDENT "in" expression block "end"
pub const ForExpr = struct {
    binding: []const u8,
    iterable: *Expr,
    body: []Stmt,
    token: Token,

    pub fn print(self: *ForExpr, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("for expr: {s}\n", .{self.binding});
        try self.iterable.print(indent + 4);
        for (0..self.body.len) |i| {
            var stmt = self.body[i];
            for (0..indent + 4) |_| std.debug.print(" ", .{});
            std.debug.print("stmt\n", .{});
            try stmt.print(indent + 4);
        }
    }
};

// comptime_expr = "comptime" block "end"
pub const ComptimeExpr = struct {
    body: []Stmt,
    token: Token,

    pub fn print(self: *ComptimeExpr, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("comptime expr\n", .{});
        for (0..self.body.len) |i| {
            var stmt = self.body[i];
            for (0..indent + 4) |_| std.debug.print(" ", .{});
            std.debug.print("stmt\n", .{});
            try stmt.print(indent + 4);
        }
    }
};

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

    pub fn print(self: *Expr, indent: usize) anyerror!void {
        switch (self.*) {
            .literal => |*l| try l.print(indent),
            .ident => |*i| try i.print(indent),
            .binary => |*b| try b.print(indent),
            .unary => |*u| try u.print(indent),
            .field_access => |*f| try f.print(indent),
            .call => |*c| try c.print(indent),
            .index => |*i| try i.print(indent),
            .optional_unwrap => |*o| try o.print(indent),
            .array_literal => |*a| try a.print(indent),
            .if_expr => |*i| try i.print(indent),
            .match_expr => |*m| try m.print(indent),
            .while_expr => |*w| try w.print(indent),
            .for_expr => |*f| try f.print(indent),
            .comptime_expr => |*c| try c.print(indent),
        }
    }
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

    pub fn print(self: *Stmt, indent: usize) anyerror!void {
        switch (self.*) {
            .var_stmt => |*v| try v.print(indent),
            .const_stmt => |*c| try c.print(indent),
            .assign_stmt => |*a| try a.print(indent),
            .local_static_var_stmt => |*l| try l.print(indent),
            .defer_stmt => |*d| try d.print(indent),
            .unsafe_stmt => |*u| try u.print(indent),
            .control_flow_stmt => |c| try c.print(indent),
            .return_stmt => |*r| try r.print(indent),
            .expr_stmt => |*e| try e.print(indent),
        }
    }
};

// var_stmt = "var" IDENT [ ":" ["?"] type ] "=" expression ";"
pub const VarStmt = struct {
    name: []const u8,
    type_ann: ?TypeAnn,
    value: *Expr,
    token: Token,

    pub fn print(self: *VarStmt, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("var stmt: {s}\n", .{self.name});
        if (self.type_ann) |*t| try t.print(indent + 4);
        try self.value.print(indent + 4);
    }
};

// const_stmt = "const" IDENT [ ":" ["?"] type ] "=" expression ";"
pub const ConstStmt = struct {
    name: []const u8,
    type_ann: ?TypeAnn,
    value: *Expr,
    token: Token,

    pub fn print(self: *ConstStmt, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("const stmt: {s}\n", .{self.name});
        if (self.type_ann) |*t| try t.print(indent + 4);
        try self.value.print(indent + 4);
    }
};

// local_static_var_stmt = "static" "var" IDENT [ ":" ["?"] type ] "=" expression ";"
pub const LocalStaticVarStmt = struct {
    name: []const u8,
    type_ann: ?TypeAnn,
    value: *Expr,
    token: Token,

    pub fn print(self: *LocalStaticVarStmt, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("local static var stmt: {s}\n", .{self.name});
        if (self.type_ann) |*t| try t.print(indent + 4);
        try self.value.print(indent + 4);
    }
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

    pub fn print(self: *CompoundOp, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("compound op: {s}\n", .{@tagName(self.*)});
    }
};

// assign_stmt = place_expr ( "=" | compound_op ) expression ";"
pub const AssignStmt = struct {
    target: *Expr,
    op: ?CompoundOp, // if null -> simple '='
    value: *Expr,
    token: Token,

    pub fn print(self: *AssignStmt, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("assign stmt\n", .{});
        try self.target.print(indent + 4);
        if (self.op) |*op| try op.print(indent + 4);
        try self.value.print(indent + 4);
    }
};

// defer_stmt = "defer" ( var_stmt | const_stmt | assign_stmt | control_flow_stmt | return_stmt | expr_stmt )
pub const DeferrableStmt = union(enum) {
    var_stmt: VarStmt,
    const_stmt: ConstStmt,
    assign_stmt: AssignStmt,
    control_flow_stmt: *Expr,
    return_stmt: ReturnStmt,
    expr_stmt: ExprStmt,

    pub fn print(self: *DeferrableStmt, indent: usize) anyerror!void {
        switch (self.*) {
            .var_stmt => |*v| try v.print(indent),
            .const_stmt => |*c| try c.print(indent),
            .assign_stmt => |*a| try a.print(indent),
            .control_flow_stmt => |c| try c.print(indent),
            .return_stmt => |*r| try r.print(indent),
            .expr_stmt => |*e| try e.print(indent),
        }
    }
};

pub const DeferStmt = struct {
    inner: *DeferrableStmt,
    token: Token,

    pub fn print(self: *DeferStmt, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("defer stmt\n", .{});
        try self.inner.print(indent + 4);
    }
};

// unsafe_stmt = "unsafe" block "end"
pub const UnsafeStmt = struct {
    body: []Stmt,
    token: Token,

    pub fn print(self: *UnsafeStmt, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("unsafe stmt\n", .{});
        for (0..self.body.len) |i| {
            var stmt = self.body[i];
            for (0..indent + 4) |_| std.debug.print(" ", .{});
            std.debug.print("stmt\n", .{});
            try stmt.print(indent + 4);
        }
    }
};

// return_stmt = return_expr ";"
pub const ReturnStmt = struct {
    value: ?*Expr,
    token: Token,

    pub fn print(self: *ReturnStmt, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("return stmt\n", .{});
        if (self.value) |v| try v.print(indent + 4);
    }
};

// expr_stmt = expression ";"
pub const ExprStmt = struct {
    value: ?*Expr,

    pub fn print(self: *ExprStmt, indent: usize) anyerror!void {
        for (0..indent) |_| std.debug.print(" ", .{});
        std.debug.print("expr stmt\n", .{});
        if (self.value) |v| try v.print(indent + 4);
    }
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
            .program = .{ .items = .empty },
        };
    }

    pub fn allocator(self: *AST) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn deinit(self: *AST) void {
        self.arena.deinit();
    }

    pub fn print(self: *AST) anyerror!void {
        std.debug.print("AST:\n", .{});
        for (self.program.items.items) |*item| {
            try item.print(2);
        }
    }
};
