const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // const dep_sokol = b.dependency("sokol", .{
    //     .target = target,
    //     .optimize = optimize,
    // });

    const exe = b.addExecutable(.{
        .name = "ray-tracer",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize }),
    });

    //exe.root_module.addImport("sokol", dep_sokol.module("sokol"));

    // Add MacOS framework dependencies
    // exe.linkFramework("Metal");
    // exe.linkFramework("Foundation");
    // exe.linkFramework("MetalPerformanceShaders");
    // exe.linkFramework("QuartzCore");
    // exe.linkFramework("Accelerate"); // For BLAS/LAPACK functions

    // Install the executable
    b.installArtifact(exe);

    // Create a run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // Add run command args if provided
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Make the run step available via `zig build run`
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
