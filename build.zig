const std = @import("std");

const Builder = std.build.Builder;

const packages = @import("deps.zig");

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    const lib_tests = b.addTest("src/main.zig");
    lib_tests.setBuildMode(mode);

    if (@hasDecl(packages, "use_submodules")) { // submodules
        const package = getPackage(b, ".");

        for (package.dependencies.?) |dep| {
            lib_tests.addPackage(dep);
        }
    } else if (@hasDecl(packages, "addAllTo")) { // zigmod
        packages.addAllTo(lib_tests);
    } else if (@hasDecl(packages, "pkgs") and @hasDecl(packages.pkgs, "addAllTo")) { // gyro
        packages.pkgs.addAllTo(lib_tests);
    }

    const tests = b.step("test", "Run all library tests");
    tests.dependOn(&lib_tests.step);
}

pub fn getPackage(b: *Builder, comptime prefix: []const u8) std.build.Pkg {
    var dependencies = b.allocator.alloc(std.build.Pkg, 4) catch unreachable;

    dependencies[0] = .{ .name = "iguanaTLS", .path = .{ .path = prefix ++ "/libs/iguanaTLS/src/main.zig" } };
    dependencies[1] = .{ .name = "network", .path = .{ .path = prefix ++ "/libs/network/network.zig" } };
    dependencies[2] = .{ .name = "uri", .path = .{ .path = prefix ++ "/libs/uri/uri.zig" } };
    dependencies[3] = .{ .name = "hzzp", .path = .{ .path = prefix ++ "/libs/hzzp/src/main.zig" } };

    return .{
        .name = "zfetch",
        .path = .{ .path = prefix ++ "/src/main.zig" },
        .dependencies = dependencies,
    };
}
