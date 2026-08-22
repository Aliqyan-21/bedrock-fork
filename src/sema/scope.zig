const std = @import("std");

pub const Scope = struct {
    names: std.StringHashMap(void), // for O(1)

    pub fn init(allocator: std.mem.Allocator) Scope {
        return .{
            .names = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *Scope) void {
        self.names.deinit();
    }

    // rule of duplication
    pub fn declare(self: *Scope, name: []const u8) !void {
        if (self.names.contains(name)) return error.DuplicateName;
        try self.names.put(name, {});
    }
};
