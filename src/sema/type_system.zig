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
        for (self.types.items) |*ty| {
            switch (ty.*) {
                .function => |*f| f.params.deinit(self.allocator),
                .procedure => |*p| p.params.deinit(self.allocator),
                else => {},
            }
        }
        self.types.deinit(self.allocator);
    }

    pub fn get(self: *TypeSystem, id: TypeId) *Type {
        std.debug.assert(id != .invalid);
        return &self.types.items[@intFromEnum(id) - 1];
    }

    pub fn add(self: *TypeSystem, ty: Type) !TypeId {
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
        var id: TypeId = switch (ty.base) {
            .primitive => |p| try self.from_ast_primitive(p),
            .pointer => |inner| blk: {
                const cid = try self.resolve_type(inner);
                break :blk try self.intern(.{ .pointer = .{ .child = cid } });
            },
            .slice => |*s| blk: {
                const cid = try self.resolve_type(s.elem);
                break :blk try self.intern(.{ .slice = .{ .child = cid } });
            },
            .array => |*a| blk: {
                const cid = try self.resolve_type(a.elem);
                break :blk switch (a.size) {
                    .fixed => |d| self.intern(.{ .array = .{ .child = cid, .len = std.fmt.parseInt(u64, d, 10) catch return .invalid } }) catch return .invalid,
                    .inferred => .invalid,
                };
            },
            .func => |*f| blk: {
                var params: std.ArrayList(TypeId) = .empty;
                for (f.params.items) |p| try params.append(self.allocator, try self.resolve_type(p));
                const rid = try self.resolve_type(f.result);
                break :blk try self.intern(.{ .function = .{ .params = params, .result = rid } });
            },
            .proc => |*pr| blk: {
                var params: std.ArrayList(TypeId) = .empty;
                for (pr.params.items) |p| try params.append(self.allocator, try self.resolve_type(p));
                break :blk try self.intern(.{ .procedure = .{ .params = params } });
            },
            .named => .invalid,
        };

        if (ty.is_optional) id = try self.intern(.{ .optional = id });
        if (ty.is_error_union) id = try self.intern(.{ .error_union = id });
        return id;
    }

    fn is_type_eql(a: Type, b: Type) bool {
        if (@as(std.meta.Tag(Type), a) != @as(std.meta.Tag(Type), b)) return false;
        return switch (a) {
            .primitive => a.primitive == b.primitive,
            .pointer => a.pointer.child == b.pointer.child,
            .array => a.array.child == b.array.child,
            .slice => a.slice.child == b.slice.child,
            .optional => a.optional == b.optional,
            .error_union => a.error_union == b.error_union,
            .function => (a.function.result == b.function.result) and
                std.mem.eql(TypeId, a.function.params.items, b.function.params.items),
            .procedure => std.mem.eql(TypeId, a.function.params.items, b.function.params.items),
        };
    }

    // function for helping in adding type to
    // our types if it does not exisit already
    // for use in resolve_type
    pub fn intern(self: *TypeSystem, ty: Type) !TypeId {
        for (self.types.items, 0..) |e, i| {
            if (is_type_eql(e, ty)) {
                return @enumFromInt(i + 1);
            }
        }
        return self.add(ty);
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
            .array => |a| std.fmt.allocPrint(self.allocator, "[{d}]{s}", .{ a.len, self.name_of(a.child) }) catch "<oom>",
            .slice => |s| std.fmt.allocPrint(self.allocator, "[]{s}", .{self.name_of(s.child)}) catch "<oom>",
            else => "not implemented",
        };
    }
};
