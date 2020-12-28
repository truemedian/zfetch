const std = @import("std");

const mem = std.mem;

const tls = @import("iguanatls");
const network = @import("network");

const SocketReader = network.Socket.Reader;
const SocketWriter = network.Socket.Writer;

const SecureContext = tls.Client(SocketReader, SocketWriter);

pub const Protocol = enum {
    http,
    https,

    pub fn defaultPort(self: Protocol) u16 {
        return switch (self) {
            .http => 80,
            .https => 443,
        };
    }
};

pub const init = network.init;
pub const deinit = network.deinit;

pub const Connection = struct {
    allocator: *mem.Allocator,
    hostname: []const u8,
    protocol: Protocol,
    port: ?u16,

    socket: network.Socket,
    context: SecureContext,

    pub fn connect(allocator: *mem.Allocator, hostname: []const u8, port: ?u16, protocol: Protocol) !*Connection {
        var conn = try allocator.create(Connection);
        errdefer allocator.destroy(conn);

        conn.allocator = allocator;
        conn.hostname = hostname;
        conn.protocol = protocol;
        conn.port = port orelse protocol.defaultPort();

        conn.socket = try network.connectToHost(allocator, hostname, port orelse protocol.defaultPort(), .tcp);
        errdefer conn.socket.close();

        switch (protocol) {
            .http => {
                conn.context = undefined;
            },
            .https => {
                conn.context = try tls.client_connect(.{
                    .rand = null,
                    .reader = conn.socket.reader(),
                    .writer = conn.socket.writer(),
                    .cert_verifier = .none,
                }, hostname);
            },
        }

        return conn;
    }

    pub fn close(self: *Connection) void {
        if (self.protocol == .https) {
            self.context.close_notify() catch {};
        }

        self.socket.close();
        self.allocator.destroy(self);
    }

    pub const ReadError = SecureContext.Reader.Error;
    pub const Reader = std.io.Reader(*Connection, ReadError, read);
    pub fn read(self: *Connection, buffer: []u8) ReadError!usize {
        return switch (self.protocol) {
            .http => self.socket.receive(buffer),
            .https => self.context.read(buffer),
        };
    }

    pub fn reader(self: *Connection) Reader {
        return .{ .context = self };
    }

    pub const WriteError = SecureContext.Writer.Error;
    pub const Writer = std.io.Writer(*Connection, WriteError, write);
    pub fn write(self: *Connection, buffer: []const u8) WriteError!usize {
        return switch (self.protocol) {
            .http => self.socket.send(buffer),
            .https => self.context.write(buffer),
        };
    }

    pub fn writer(self: *Connection) Writer {
        return .{ .context = self };
    }
};

test "can http?" {
    try network.init();
    var conn = try Connection.connect(std.testing.allocator, "en.wikipedia.org", null, .http);
    defer conn.close();

    try conn.writer().writeAll("GET / HTTP/1.1\r\nHost: en.wikipedia.org\r\nAccept: */*\r\n\r\n");

    var buf = try conn.reader().readUntilDelimiterAlloc(std.testing.allocator, '\r', std.math.maxInt(usize));
    defer std.testing.allocator.free(buf);

    std.testing.expectEqualStrings("HTTP/1.1 301 TLS Redirect", buf);
}

test "can https?" {
    try network.init();
    var conn = try Connection.connect(std.testing.allocator, "en.wikipedia.org", null, .https);
    defer conn.close();

    try conn.writer().writeAll("GET / HTTP/1.1\r\nHost: en.wikipedia.org\r\nAccept: */*\r\n\r\n");

    var buf = try conn.reader().readUntilDelimiterAlloc(std.testing.allocator, '\r', std.math.maxInt(usize));
    defer std.testing.allocator.free(buf);

    std.testing.expectEqualStrings("HTTP/1.1 301 Moved Permanently", buf);
}

comptime {
    std.testing.refAllDecls(@This());
}
