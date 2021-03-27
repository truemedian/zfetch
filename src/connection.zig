const std = @import("std");

const mem = std.mem;

const tls = @import("iguanaTLS");
const network = @import("network");

const SocketReader = network.Socket.Reader;
const SocketWriter = network.Socket.Writer;

const SecureContext = tls.Client(SocketReader, SocketWriter, tls.ciphersuites.all, true);

/// The protocol which a connection should use. This dictates the default port and whether or not a TLS connection
/// should be established.
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

/// A wrapper around TCP + TLS and raw TCP streams that provides a connection agnostic interface.
pub const Connection = struct {
    allocator: *mem.Allocator,

    /// The hostname that this connection was initiated with.
    hostname: []const u8,

    /// The protocol that this connection was initiated with.
    protocol: Protocol,

    /// The port that this connection was initiated with.
    port: u16,

    /// The underlying network socket.
    socket: network.Socket,

    /// The TLS context if the connection is using TLS.
    context: SecureContext = undefined,

    /// The TLS context's trust chain.
    trust_chain: ?tls.x509.CertificateChain = null,

    /// Form a connection to the requested hostname and port.
    pub fn connect(allocator: *mem.Allocator, hostname: []const u8, port: ?u16, protocol: Protocol, trust_chain: ?tls.x509.CertificateChain) !Connection {
        const host_dupe = try allocator.dupe(u8, hostname);

        var conn = Connection{
            .allocator = allocator,
            .hostname = host_dupe,
            .protocol = protocol,
            .port = port orelse protocol.defaultPort(),
            .socket = try network.connectToHost(allocator, host_dupe, port orelse protocol.defaultPort(), .tcp),
            .trust_chain = trust_chain,
        };
        errdefer conn.socket.close();

        try conn.setupTlsContext(trust_chain);

        return conn;
    }

    pub fn reconnect(self: *Connection) !void {
        conn.socket.close();

        if (self.protocol == .https) {
            self.context.close_notify() catch {};
        }

        conn.socket = try network.connectToHost(self.allocator, self.hostname, self.port, .tcp);

        if (self.protocol == .https) {
            try conn.setupTlsContext(self.trust_chain);
        }
    }

    fn setupTlsContext(self: *Connection, trust: ?tls.x509.CertificateChain) !void {
        switch (self.protocol) {
            .http => {
                self.context = undefined;
            },
            .https => {
                if (trust) |trust_chain| {
                    self.context = try tls.client_connect(.{
                        .reader = self.socket.reader(),
                        .writer = self.socket.writer(),
                        .cert_verifier = .default,
                        .trusted_certificates = trust_chain.data.items,
                        .temp_allocator = self.allocator,
                        .ciphersuites = tls.ciphersuites.all,
                        .protocols = &[_][]const u8{"http/1.1"},
                    }, self.hostname);
                } else {
                    self.context = try tls.client_connect(.{
                        .reader = self.socket.reader(),
                        .writer = self.socket.writer(),
                        .cert_verifier = .none,
                        .temp_allocator = self.allocator,
                        .ciphersuites = tls.ciphersuites.all,
                        .protocols = &[_][]const u8{"http/1.1"},
                    }, self.hostname);
                }
            },
        }
    }

    /// Close this connection.
    pub fn close(self: *Connection) void {
        if (self.protocol == .https) {
            self.context.close_notify() catch {};
        }

        self.socket.close();
        self.allocator.free(self.hostname);
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
    var conn = try Connection.connect(std.testing.allocator, "en.wikipedia.org", null, .http, null);
    defer conn.close();

    try conn.writer().writeAll("GET / HTTP/1.1\r\nHost: en.wikipedia.org\r\nAccept: */*\r\n\r\n");

    var buf = try conn.reader().readUntilDelimiterAlloc(std.testing.allocator, '\r', std.math.maxInt(usize));
    defer std.testing.allocator.free(buf);

    std.testing.expectEqualStrings("HTTP/1.1 301 TLS Redirect", buf);
}

test "can https?" {
    try network.init();
    var conn = try Connection.connect(std.testing.allocator, "en.wikipedia.org", null, .https, null);
    defer conn.close();

    try conn.writer().writeAll("GET / HTTP/1.1\r\nHost: en.wikipedia.org\r\nAccept: */*\r\n\r\n");

    var buf = try conn.reader().readUntilDelimiterAlloc(std.testing.allocator, '\r', std.math.maxInt(usize));
    defer std.testing.allocator.free(buf);

    std.testing.expectEqualStrings("HTTP/1.1 301 Moved Permanently", buf);
}

comptime {
    std.testing.refAllDecls(@This());
}
