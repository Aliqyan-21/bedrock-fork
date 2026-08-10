const Token = @import("token.zig").Token;

pub const Severity = enum {
    Error,
    Note,
};

pub const SourceError = struct {
    msg: []const u8,
    severity: Severity,
    token: Token,
};
