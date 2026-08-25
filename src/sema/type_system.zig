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
    //todo: implement other types
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

    // this does same work as visit type but now returns the typeid too,
    // as it will become complete then there will be no need for visit_type, then
    // just resolve_type will be used everywhere then we can remove visit_type
    pub fn resolve_type(self: *TypeSystem, ty: *ast.Type) !TypeId {
        return switch (ty.base) {
            .primitive => |p| try self.from_ast_primitive(p),
            else => .invalid, // pointer,array,etc...
        };
    }

    // for mapping ast primitive to sema primitive
    pub fn from_ast_primitive(self: *TypeSystem, p: ast.PrimitiveType) !TypeId {
        const mapped = std.meta.stringToEnum(Primitive, @tagName(p)) orelse unreachable;
        return self.primitive(mapped);
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

    pub fn is_numeric(self: *TypeSystem, id: TypeId) bool {
        if (id == .invalid) return false;
        return switch (self.get(id).primitive) {
            .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .f32, .f64, .usize, .isize => true,
            else => false,
        };
    }

    pub fn name_of(self: *TypeSystem, id: TypeId) []const u8 {
        if (id == .invalid) return "<invalid>";
        return switch (self.get(id).*) {
            .primitive => |p| @tagName(p),
        };
    }

    //todo: implment more functions for other types
};
