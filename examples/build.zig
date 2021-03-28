const std = @import("std");

const Builder = std.build.Builder;

const packages = @import("deps.zig");

const examples = [_][]const u8{"get", "post", "download"};

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    inline for (examples) |name| {
        const example = b.addExecutable(name, name ++ ".zig");
        example.setBuildMode(mode);
        example.install();

        if (@hasDecl(packages, "addAllTo")) { // zigmod
            packages.addAllTo(example);
        } else if (@hasDecl(packages, "pkgs") and @hasDecl(packages.pkgs, "addAllTo")) { // gyro
            packages.pkgs.addAllTo(example);
        }

        const example_step = b.step(name, "Build the " ++ name ++ " example");
        example_step.dependOn(&example.step);

        const example_run_step = b.step(name ++ "-run", "Run the " ++ name ++ " example");

        const example_run = example.run();
        example_run_step.dependOn(&example_run.step);
    }
}
