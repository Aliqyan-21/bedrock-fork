const std = @import("std");

var arena: std.heap.ArenaAllocator = undefined;

export fn bok_init() void {
    arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
}

export fn bok_alloc(size: usize) *anyopaque {
    var a = arena;
    const memory = a.allocator().alignedAlloc(u8, .@"64", size) catch @panic("bok_alloc failed");
    return memory.ptr;
}

export fn bok_deinit() void {
    arena.deinit();
}
