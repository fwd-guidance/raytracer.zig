const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const exe = b.addExecutable(.{
        .name = "ray-tracer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{
                    .name = "c",
                    .module = translate_c.createModule(),
                },
            },
        }),
    });

    exe.root_module.addCSourceFile(.{
        .file = b.path("src/stb_image_impl.c"),
        .flags = &.{"-std=c99"},
    });

    exe.root_module.addIncludePath(b.path("src"));

    // Install the executable
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the main app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.addPassthruArgs();
}
