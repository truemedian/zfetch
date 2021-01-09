const std = @import("std");

const ascii = std.ascii;
const mem = std.mem;
const fmt = std.fmt;

const hzzp = @import("hzzp");
const zuri = @import("uri");

const conn = @import("connection.zig");

const Protocol = conn.Protocol;
const Connection = conn.Connection;

// RFC 7231 and RFC 5789
pub const Method = enum {
    GET,
    HEAD,
    POST,
    PUT,
    DELETE,
    CONNECT,
    OPTIONS,
    TRACE,
    PATCH,

    pub fn name(self: Method) []const u8 {
        return @tagName(self);
    }

    pub const HasPayload = enum { yes, no, maybe };
    pub fn hasPayload(self: Method) HasPayload {
        switch (self) {
            .GET, .HEAD, .CONNECT, .OPTIONS, .TRACE => return .no,
            .POST, .PUT, .PATCH => return .yes,
            .DELETE => return .maybe,
        }
    }
};

const root = @import("root");
pub const use_buffered_io: bool = if (@hasDecl(root, "zfetch_use_buffered_io"))
    root.zfetch_use_buffered_io
else
    true;

const BufferedReader = std.io.BufferedReader(4096, Connection.Reader);
const BufferedWriter = std.io.BufferedWriter(4096, Connection.Writer);

const HttpClient = if (use_buffered_io)
    hzzp.base.client.BaseClient(BufferedReader.Reader, BufferedWriter.Writer)
else
    hzzp.base.client.BaseClient(Connection.Reader, Connection.Writer);

pub const Request = struct {
    pub const Status = struct {
        code: u16,
        reason: []const u8,
    };

    allocator: *mem.Allocator,
    socket: *Connection,

    url: []const u8,
    uri: zuri.UriComponents,

    buffer: []u8 = undefined,
    client: HttpClient,

    status: Status,
    headers: hzzp.Headers,

    buffered_reader: if (use_buffered_io) BufferedReader else void,
    buffered_writer: if (use_buffered_io) BufferedWriter else void,

    // assumes scheme://hostname[:port]/ url
    pub fn init(allocator: *mem.Allocator, url: []const u8) !*Request {
        const url_safe = try allocator.dupe(u8, url);
        const uri = try zuri.parse(url_safe);

        const protocol: Protocol = proto: {
            if (uri.scheme) |scheme| {
                if (mem.eql(u8, scheme, "http")) {
                    break :proto .http;
                } else if (mem.eql(u8, scheme, "https")) {
                    break :proto .https;
                } else {
                    return error.InvalidScheme;
                }
            } else {
                return error.MissingScheme;
            }
        };

        var req = try allocator.create(Request);
        errdefer allocator.destroy(req);

        if (uri.host == null) return error.MissingHost;

        req.allocator = allocator;
        req.socket = try Connection.connect(allocator, uri.host.?, uri.port, protocol);

        req.buffer = try allocator.alloc(u8, mem.page_size);

        req.url = url_safe;
        req.uri = uri;

        if (comptime use_buffered_io) {
            req.buffered_reader = BufferedReader{ .unbuffered_reader = req.socket.reader() };
            req.buffered_writer = BufferedWriter{ .unbuffered_writer = req.socket.writer() };

            req.client = HttpClient.init(req.buffer, req.buffered_reader.reader(), req.buffered_writer.writer());
        } else {
            req.client = HttpClient.init(req.buffer, req.socket.reader(), req.socket.writer());
        }

        req.headers = hzzp.Headers.init(allocator);
        req.status = Status{
            .code = 0,
            .reason = "",
        };

        return req;
    }

    pub fn deinit(self: *Request) void {
        self.socket.close();
        self.headers.deinit();

        self.uri = undefined;

        self.allocator.free(self.url);
        self.allocator.free(self.buffer);
        self.allocator.free(self.status.reason);

        self.allocator.destroy(self);
    }

    pub fn commit(self: *Request, method: Method, headers: hzzp.Headers, payload: ?[]const u8) !void {
        if (method.hasPayload() == .yes and payload == null) return error.MissingPayload;
        if (method.hasPayload() == .no and payload != null) return error.MustOmitPayload;

        try self.client.writeStatusLineParts(method.name(), self.uri.path orelse "/", self.uri.query, self.uri.fragment);

        if (!headers.contains("Host")) {
            try self.client.writeHeaderValue("Host", self.uri.host.?);
        }

        if (self.uri.user != null or self.uri.password != null) {
            if (self.uri.user == null) return error.MissingUsername;
            if (self.uri.password == null) return error.MissingPassword;

            if (headers.contains("Authorization")) return error.AuthorizationMismatch;

            var unencoded = try fmt.allocPrint(self.allocator, "{s}:{s}", .{ self.uri.user, self.uri.password });
            defer self.allocator.free(unencoded);

            var auth = try self.allocator.alloc(u8, std.base64.standard_encoder.calcSize(unencoded.len));
            defer self.allocator.free(auth);

            std.base64.standard_encoder.encode(auth, unencoded);

            try self.client.writeHeaderValueFormat("Authorization", "Basic {s}", .{auth});
        }

        if (!headers.contains("User-Agent")) {
            try self.client.writeHeaderValue("User-Agent", "zfetch");
        }

        if (!headers.contains("Connection")) {
            try self.client.writeHeaderValue("Connection", "close");
        }

        try self.client.writeHeaders(headers.list.items);
        try self.client.finishHeaders();
        try self.client.writePayload(payload);

        if (comptime use_buffered_io) {
            try self.buffered_writer.flush();
        }
    }

    pub fn fulfill(self: *Request) !void {
        while (try self.client.next()) |event| {
            switch (event) {
                .status => |stat| {
                    self.status.code = stat.code;
                    self.status.reason = try self.allocator.dupe(u8, stat.reason);
                },
                .header => |header| {
                    try self.headers.append(header);
                },
                .head_done => {
                    return;
                },
                .skip => {},
                .payload, .end => unreachable,
            }
        }
    }

    pub const Reader = HttpClient.PayloadReader;
    pub fn reader(self: *Request) Reader {
        return self.client.reader();
    }
};

test "" {
    try conn.init();
    defer conn.deinit();

    var headers = hzzp.Headers.init(std.testing.allocator);
    defer headers.deinit();

    var req = try Request.init(std.testing.allocator, "https://discord.com/");
    defer req.deinit();

    try req.commit(.GET, headers, null);
    try req.fulfill();

    std.testing.expect(req.status.code == 200);
    std.testing.expectEqualStrings("OK", req.status.reason);
    std.testing.expectEqualStrings("text/html", req.headers.get("content-type").?);
    std.testing.expectEqualStrings("cloudflare", req.headers.get("server").?);
    std.testing.expectEqualStrings("close", req.headers.get("connection").?);

    var buf: [34]u8 = undefined;
    _ = try req.reader().read(&buf);

    std.testing.expectEqualStrings("<!DOCTYPE html><html lang=\"en-US\">", &buf);
}

comptime {
    std.testing.refAllDecls(@This());
}
