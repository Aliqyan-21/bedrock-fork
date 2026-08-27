const std = @import("std");
const ast = @import("../ast.zig");

pub const TypeId = enum(u32) {
    invalid = 0,
    _,
};

pub const Primitive = enum {
    // zig fmt: off
    bool, char, str,
    i8, i16, i32, i64,
    u8, u16, u32, u64,
    f32, f64,
    usize, isize,
    // zig fmt: on
};

pub const Type = union(enum) {
    primitive: Primitive,
    pointer: struct { child: TypeId },
    array: struct { child: TypeId, len: u64 },
    slice: struct { child: TypeId },
    optional: TypeId,
    error_union: TypeId,
    function: struct { params: std.ArrayList(TypeId), result: TypeId },
    procedure: struct { params: std.ArrayList(TypeId) },
};

pub const TypeSystem = struct {
    allocator: std.mem.Allocator,
    types: std.ArrayList(Type),

    pids: [@typeInfo(Primitive).@"enum".fields.len]TypeId, // primtive ids

    pub fn init(allocator: std.mem.Allocator) TypeSystem {
        return .{
            .allocator = allocator,
            .types = .empty,
            .pids = [_]TypeId{.invalid} ** @typeInfo(Primitive).@"enum".fields.len,
        };
    }

    pub fn deinit(self: *TypeSystem) void {
        self.types.deinit(self.allocator);
    }

    pub fn get(self: *TypeSystem, id: TypeId) *Type {
        std.debug.assert(id != .invalid);
        return &self.types.items[@intFromEnum(id) - 1];
    }

    fn add(self: *TypeSystem, ty: Type) !TypeId {
        try self.types.append(self.allocator, ty);
        return @enumFromInt(self.types.items.len);
    }

    pub fn primitive(self: *TypeSystem, p: Primitive) !TypeId {
        const idx = @intFromEnum(p);
        if (self.pids[idx] != .invalid) {
            return self.pids[idx];
        }
        const id = try self.add(.{ .primitive = p });
        self.pids[idx] = id;
        return id;
    }

    //todo: implment other types

    // this does same work as visit type but now returns the typeid too,
    // as it will become complete then there will be no need for visit_type, then
    // just resolve_type will be used everywhere then we can remove visit_type
    pub fn resolve_type(self: *TypeSystem, ty: *ast.Type) !TypeId {
        return switch (ty.base) {
            .primitive => |p| try self.from_ast_primitive(p),
            //todo: implement pointer after discussion.
            else => .invalid, // pointer,array,etc...
        };
    }

    // for mapping ast primitive to sema primitive
    pub fn from_ast_primitive(self: *TypeSystem, p: ast.PrimitiveType) !TypeId {
        const mapped = std.meta.stringToEnum(Primitive, @tagName(p)) orelse unreachable;
        return self.primitive(mapped);
    }

    pub fn body_returns(self: TypeSystem, stms: []ast.Stmt) bool {
        if (stms.len == 0) return false;
        return switch (stms[stms.len - 1]) {
            .return_stmt => true,
            .control_flow_stmt => |cf| switch (cf) {
                .if_expr => |i| blk: {
                    const eb = i.else_body orelse break :blk false;
                    if (!self.body_returns(i.then_body.items)) break :blk false;
                    for (i.elifs.items) |e| if (!self.body_returns(e.body.items)) break :blk false;
                    break :blk self.body_returns(eb.items);
                },
                .match_expr => |m| blk: {
                    const eb = m.else_body orelse break :blk false;
                    for (m.arms.items) |arm| if (!self.body_returns(arm.body.items)) break :blk false;
                    break :blk self.body_returns(eb.items);
                },
                else => false,
            },
            else => false,
        };
    }

    // to check if an id (from) can be assign to another id (to)
    // it's useful for type conversion checking.
    pub fn assignable(self: *TypeSystem, from: TypeId, to: TypeId) bool {
        if (from == .invalid or to == .invalid) return true;
        if (from == to) return true;
        return switch (self.get(to).*) {
            .optional => |inner| from == inner or self.assignable(from, inner),
            .error_union => |inner| from == inner or self.assignable(from, inner),
            else => false,
        };
    }

    // find type of literal "hi" -> string, 24 -> i32
    pub fn literal_type(self: *TypeSystem, kind: ast.LiteralKind) !TypeId {
        return switch (kind) {
            .integer => self.primitive(.i32),
            .float => self.primitive(.f64),
            .string => self.primitive(.str),
            .char => self.primitive(.char),
            .bool_true, .bool_false => self.primitive(.bool),
        };
    }

    // does literal fits this type
    pub fn literal_fits(self: *TypeSystem, kind: ast.LiteralKind, id: TypeId) bool {
        if (id == .invalid) return false;
        const p = switch (self.get(id).*) {
            .primitive => |p| p,
            else => return false,
        };
        return switch (kind) {
            .integer => switch (p) {
                .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .f32, .f64, .usize, .isize => true,
                else => false,
            },
            .float => switch (p) {
                .f32, .f64 => true,
                else => false,
            },
            else => false,
        };
    }

    pub fn name_of(self: *TypeSystem, id: TypeId) []const u8 {
        if (id == .invalid) return "<invalid>";
        return switch (self.get(id).*) {
            .primitive => |p| @tagName(p),
            else => "not implemented",
        };
    }
};
