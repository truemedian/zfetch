const std = @import("std");

const Builder = std.build.Builder;

const packages = @import("deps.zig");

pub fn build(b: *Builder) void {
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
