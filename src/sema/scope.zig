const std = @import("std");

pub const SymbolKind = enum {
    variable,
    constant,
    param,
    func,
    proc,
};

pub const Symbol = struct {
    name: []const u8,
    kind: SymbolKind,
    // here we keep growing accordingly,
    // like storing types, etc.
};

pub const Scope = struct {
    symbols: std.StringHashMap(Symbol), // for O(1)

    pub fn init(allocator: std.mem.Allocator) Scope {
        return .{
            .symbols = std.StringHashMap(Symbol).init(allocator),
        };
    }

    pub fn deinit(self: *Scope) void {
        self.symbols.deinit();
    }

    // rule of duplication
    pub fn declare(self: *Scope, symbol: Symbol) !void {
        if (self.symbols.contains(symbol.name)) return error.DuplicateName;
        try self.symbols.put(symbol.name, symbol);
    }
};
