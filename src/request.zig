const std = @import("std");

const mem = std.mem;

const hzzp = @import("hzzp");
const conn = @import("conn.zig");

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

pub const PartialUri = struct {
    href: []const u8 = undefined,
    scheme: []const u8 = undefined,
    hostname: []const u8 = undefined,
    port: ?[]const u8 = null,
    path: []const u8 = "/",

    pub fn parse(input: []const u8) !PartialUri {
        var len: usize = 0;
        var uri = PartialUri{};

        uri.href = input;

        for (input) |char, i| {
            switch (char) {
                'a'...'z' => {},
                ':' => {
                    uri.scheme = input[0..i];
                    len = i;
                    break;
                },
                else => return error.InvalidScheme,
            }
        }

        if (input.len < len + 2 or input[len + 1] != '/' or input[len + 2] != '/') return error.InvalidUrl;
        len += 3;

        for (input[len..]) |char, i| {
            switch (char) {
                ':' => {
                    uri.hostname = input[len .. len + i];
                    len += i;
                    break;
                },
                '/' => {
                    uri.hostname = input[len .. len + i];
                    uri.path = input[len + i ..];
                    return uri;
                },
                else => {},
            }
        }

        len += 1;

        for (input[len..]) |char, i| {
            switch (char) {
                '/' => {
                    uri.port = input[len .. len + i];
                    uri.path = input[len + i ..];
                    return uri;
                },
                else => {},
            }
        }

        uri.hostname = input[len - 1 ..];
        return uri;
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
    uri: PartialUri,

    buffer: [mem.page_size]u8 = undefined,
    client: HttpClient,

    status: Status,
    headers: hzzp.Headers,

    buffered_reader: if (use_buffered_io) BufferedReader else void,
    buffered_writer: if (use_buffered_io) BufferedWriter else void,

    // assumes scheme://hostname[:port]/ url
    pub fn init(allocator: *mem.Allocator, url: []const u8) !*Request {
        var url_safe = try allocator.dupe(u8, url);
        var uri = try PartialUri.parse(url_safe);

        const protocol: Protocol = proto: {
            if (mem.eql(u8, uri.scheme, "http")) {
                break :proto .http;
            } else if (mem.eql(u8, uri.scheme, "https")) {
                break :proto .https;
            } else {
                return error.InvalidScheme;
            }
        };

        const port = port: {
            if (uri.port) |p| {
                break :port try std.fmt.parseUnsigned(u16, p, 10);
            }

            break :port null;
        };

        var req = try allocator.create(Request);
        errdefer allocator.destroy(req);

        req.allocator = allocator;
        req.socket = try Connection.connect(allocator, uri.hostname, port, protocol);
        req.uri = uri;

        if (comptime use_buffered_io) {
            req.buffered_reader = BufferedReader{ .unbuffered_reader = req.socket.reader() };
            req.buffered_writer = BufferedWriter{ .unbuffered_writer = req.socket.writer() };
            
            req.client = HttpClient.init(&req.buffer, req.buffered_reader.reader(), req.buffered_writer.writer());
        } else {
            req.client = HttpClient.init(&req.buffer, req.socket.reader(), req.socket.writer());
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

        self.allocator.free(self.uri.href);
        self.allocator.free(self.status.reason);

        self.allocator.destroy(self);
    }

    pub fn commit(self: *Request, method: Method, headers: hzzp.Headers, payload: ?[]const u8) !void {
        if (method.hasPayload() == .yes and payload == null) return error.MissingPayload;
        if (method.hasPayload() == .no and payload != null) return error.MustOmitPayload;

        try self.client.writeStatusLine(method.name(), self.uri.path);
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
    
    var timer = std.time.Timer.start() catch unreachable;

    var headers = hzzp.Headers.init(std.testing.allocator);
    defer headers.deinit();

    try headers.set("Host", "discord.com");
    try headers.set("Connection", "close");

    var req = try Request.init(std.testing.allocator, "https://discord.com/");
    defer req.deinit();
    
    try req.commit(.GET, headers, null);

    try req.fulfill();

    std.testing.expect(req.status.code == 200);
    std.testing.expectEqualStrings("OK", req.status.reason);
    std.testing.expectEqualStrings("text/html", req.headers.get("content-type").?);
    std.testing.expectEqualStrings("cloudflare", req.headers.get("server").?);
    std.testing.expectEqualStrings("close", req.headers.get("connection").?);
}

comptime {
    std.testing.refAllDecls(@This());
}
