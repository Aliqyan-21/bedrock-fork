const std = @import("std");

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
};
