const std = @import("std");

const Builder = std.build.Builder;

const examples = [_][]const u8{ "get", "post", "download", "evented" };

const submodules = false;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    inline for (examples) |name| {
        const example = b.addExecutable(name, name ++ ".zig");
        example.setBuildMode(mode);
        example.setTarget(target);
        example.install();

        if (comptime submodules) {
            example.addPackage(getPackage(b, ".."));
        } else {
            const packages = @import("deps.zig");
            if (@hasDecl(packages, "addAllTo")) { // zigmod
                packages.addAllTo(example);
            } else if (@hasDecl(packages, "pkgs") and @hasDecl(packages.pkgs, "addAllTo")) { // gyro
                packages.pkgs.addAllTo(example);
            }
        }

        const example_step = b.step(name, "Build the " ++ name ++ " example");
        example_step.dependOn(&example.step);

        const example_run_step = b.step("run-" ++ name, "Run the " ++ name ++ " example");

        const example_run = example.run();
        example_run_step.dependOn(&example_run.step);
    }
}

// can't import zfetch build.zig here, it is outside of the example's package
fn getPackage(b: *Builder, comptime prefix: []const u8) std.build.Pkg {
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
