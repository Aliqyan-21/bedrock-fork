const std = @import("std");

pub const TypeId = enum(u32) {
    invalid = 0,
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

    pub fn init(allocator: std.mem.Allocator) TypeSystem {
        return .{
            .allocator = allocator,
            .types = .{},
        };
    }

    pub fn deinit(self: *TypeSystem) void {
        self.types.deinit(self.Allocator);
    }

    pub fn get(self: TypeSystem, id: TypeId) Type {
        std.debug.assert(id != .invalid);
        return &self.types.items[@intFromEnum(id) - 1];
    }

    fn add(self: *TypeSystem, ty: Type) !TypeId {
        try self.types.append(self.allocator, ty);
        return @enumFromInt(self.types.items.len);
    }

    pub fn primitive(self: *TypeSystem, p: Primitive) !TypeId {
        return self.add(.{ .primitive = p });
    }
};
