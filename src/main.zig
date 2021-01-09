const std = @import("std");

const hzzp = @import("hzzp");

const request = @import("request.zig");
const connection = @import("connection.zig");

pub const Headers = hzzp.Headers;

pub const Request = request.Request;
pub const Method = request.Method;

pub const Connection = connection.Connection;
pub const Protocol = connection.Protocol;

comptime {
    std.testing.refAllDecls(@This());
}
