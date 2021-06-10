const std = @import("std");

const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const packages = @import("deps.zig");

    const mode = b.standardReleaseOptions();

    const lib_tests = b.addTest("src/main.zig");
    lib_tests.setBuildMode(mode);

    if (@hasDecl(packages, "addAllTo")) { // zigmod
        packages.addAllTo(lib_tests);
    } else if (@hasDecl(packages, "pkgs") and @hasDecl(packages.pkgs, "addAllTo")) { // gyro
        packages.pkgs.addAllTo(lib_tests);
    }

    const tests = b.step("test", "Run all library tests");
    tests.dependOn(&lib_tests.step);
}

pub fn getPackage(b: *Builder, comptime prefix: []const u8) std.build.Pkg {
    var dependencies = b.allocator.alloc(std.build.Pkg, 4) catch unreachable;

    dependencies[0] = .{ .name = "iguanaTLS", .path = prefix ++ "/libs/iguanaTLS/src/main.zig" };
    dependencies[1] = .{ .name = "network", .path = prefix ++ "/libs/network/network.zig" };
    dependencies[2] = .{ .name = "uri", .path = prefix ++ "/libs/uri/uri.zig" };
    dependencies[3] = .{ .name = "hzzp", .path = prefix ++ "/libs/hzzp/src/main.zig" };

    return .{
        .name = "zfetch",
        .path = prefix ++ "/src/main.zig",
        .dependencies = dependencies,
    };
}
