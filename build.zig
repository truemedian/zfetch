const std = @import("std");

const Builder = std.build.Builder;

const packages = @import("deps.zig");

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    const lib_tests = b.addTest("src/main.zig");
    lib_tests.setBuildMode(mode);

    if (@hasDecl(packages, "addAllTo")) { // zigmod
        packages.addAllTo(lib_tests);
    } else { // zkg
        inline for (std.meta.fields(@TypeOf(packages.pkgs))) |field| {
            lib_tests.addPackage(@field(packages.pkgs, field.name));
        }
    }

    const tests = b.step("test", "Run all library tests");
    tests.dependOn(&lib_tests.step);
}
