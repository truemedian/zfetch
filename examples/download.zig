const std = @import("std");

const zfetch = @import("zfetch");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = &gpa.allocator;
    defer _ = gpa.deinit();

    var headers = zfetch.Headers.init(allocator);
    defer headers.deinit();

    try headers.appendValue("Accept", "application/json");

    var req = try zfetch.Request.init(allocator, "https://www.damienelliott.com/wp-content/uploads/2020/07/1-Million-Digits-of-Pi-%CF%80.txt", null);
    defer req.deinit();

    try req.do(.GET, headers, null);

    const stdout = std.io.getStdOut().writer();
    const file = try std.fs.cwd().createFile("file.txt", .{});
    const writer = file.writer();

    if (req.status.code != 200) {
        std.log.err("request failed", .{});
    }

    const reader = req.reader();

    var buf: [16384]u8 = undefined;
    while (true) {
        const read = try reader.read(&buf);
        if (read == 0) break;

        try writer.writeAll(buf[0..read]);
    }
}
