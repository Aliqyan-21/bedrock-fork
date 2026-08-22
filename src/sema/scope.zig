const std = @import("std");

pub const Scope = struct {
    pub fn init(allocator: std.mem.Allocator) Scope {
        _ = allocator;
        return .{};
    }

    pub fn deinit(self: *Scope) void {
        _ = self;
    }
};
