const std = @import("std");

const tls = @import("iguanaTLS");
const network = @import("network");

pub const Backend = enum {
    network,
    std,
    experimental,
};

const backend: Backend = std.meta.globalOption("zfetch_backend", Backend) orelse .network;

const Socket = switch (backend) {
    .network => network.Socket,
    .std => std.net.Stream,
    .experimental => std.x.net.tcp.Client,
};

// std.x.net.tcp.Client's "Reader" decl is not a std.io.Reader.
const SocketReader = @typeInfo(@TypeOf(Socket.reader)).Fn.return_type.?;
const SocketWriter = @typeInfo(@TypeOf(Socket.writer)).Fn.return_type.?;

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
    allocator: std.mem.Allocator,

    /// The hostname that this connection was initiated with.
    hostname: []const u8,

    /// The protocol that this connection was initiated with.
    protocol: Protocol,

    /// The port that this connection was initiated with.
    port: u16,

    /// The underlying network socket.
    socket: Socket,

    /// The TLS context if the connection is using TLS.
    context: SecureContext = undefined,

    /// The TLS context's trust chain.
    trust_chain: ?tls.x509.CertificateChain = null,

    /// Form a connection to the requested hostname and port.
    pub fn connect(allocator: std.mem.Allocator, hostname: []const u8, port: ?u16, protocol: Protocol, trust_chain: ?tls.x509.CertificateChain) !Connection {
        const host_dupe = try allocator.dupe(u8, hostname);
        errdefer allocator.free(host_dupe);

        const real_port = port orelse protocol.defaultPort();
        const socket = switch (backend) {
            .network => try network.connectToHost(allocator, host_dupe, real_port, .tcp),
            .std => try std.net.tcpConnectToHost(allocator, host_dupe, real_port),
            .experimental => @compileError("backend not yet supported, std.x.net does not support hostname resolution, connect will not work"),
        };

        var conn = Connection{
            .allocator = allocator,
            .hostname = host_dupe,
            .protocol = protocol,
            .port = real_port,
            .socket = socket,
            .trust_chain = trust_chain,
        };
        errdefer conn.socket.close();

        try conn.setupTlsContext(trust_chain);

        return conn;
    }

    pub fn reconnect(self: *Connection) !void {
        self.socket.close();

        if (self.protocol == .https) {
            self.context.close_notify() catch {};
        }

        self.socket = switch (backend) {
            .network => try network.connectToHost(self.allocator, self.host_dupe, self.port, .tcp),
            .std => try std.net.tcpConnectToHost(self.allocator, self.host_dupe, self.port),
            .experimental => @compileError("backend not yet supported, std.x.net does not support hostname resolution"),
        };

        if (self.protocol == .https) {
            try self.setupTlsContext(self.trust_chain);
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
            .http => switch (backend) {
                .network => self.socket.receive(buffer),
                .std => self.socket.read(buffer),
                .experimental => @compileError("backend not yet supported, std.x.net does not support hostname resolution"),
            },
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
            .http => switch (backend) {
                .network => self.socket.send(buffer),
                .std => self.socket.write(buffer),
                .experimental => @compileError("backend not yet supported, std.x.net does not support hostname resolution"),
            },
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

    try std.testing.expectEqualStrings("HTTP/1.1 301 TLS Redirect", buf);
}

test "can https?" {
    try network.init();
    var conn = try Connection.connect(std.testing.allocator, "en.wikipedia.org", null, .https, null);
    defer conn.close();

    try conn.writer().writeAll("GET / HTTP/1.1\r\nHost: en.wikipedia.org\r\nAccept: */*\r\n\r\n");

    var buf = try conn.reader().readUntilDelimiterAlloc(std.testing.allocator, '\r', std.math.maxInt(usize));
    defer std.testing.allocator.free(buf);

    try std.testing.expectEqualStrings("HTTP/1.1 301 Moved Permanently", buf);
}

comptime {
    std.testing.refAllDecls(@This());
}
