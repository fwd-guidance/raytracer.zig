const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wgpu_native_dep = b.dependency("wgpu_native_zig", .{}).module("wgpu");
    const exe = b.addExecutable(.{
        .name = "ray-tracer",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    //const wgpu_native_dep = b.dependency("wgpu_native_zig", .{}).module("wgpu");
    exe.root_module.addImport("wgpu", wgpu_native_dep);

    // Link required system libraries for C and C++
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("c++");

    // Add MLX-C header include paths
    //exe.addIncludePath(b.path("mlx-c"));
    //exe.addIncludePath(b.path("mlx-c/mlx/c"));

    // Add wgpu-native header include paths
    exe.addIncludePath(b.path("wgpu-native/ffi"));
    exe.addIncludePath(b.path("wgpu-native/ffi/webgpu-headers"));

    // Add Tracy include path
    //exe.addIncludePath(b.path("tracy/public"));

    // Link Tracy

    // Link the static libraries in the correct order
    // MLX-C wrapper library
    //exe.addObjectFile(b.path("mlx-c/build/libmlxc.a"));
    // Main MLX library
    //exe.addObjectFile(b.path("mlx-c/build/_deps/mlx-build/libmlx.a"));
    // wgpu-native library
    //exe.addObjectFile(b.path("wgpu-native/target/debug/libwgpu_native.a"));
    // Alternatively, if using the dynamic library:
    // exe.addLibraryPath(b.path("wgpu-native/target/debug"));
    // exe.linkSystemLibrary("wgpu_native");

    // Add MacOS framework dependencies
    exe.linkFramework("Metal");
    exe.linkFramework("Foundation");
    exe.linkFramework("MetalPerformanceShaders");
    exe.linkFramework("QuartzCore");
    exe.linkFramework("Accelerate"); // For BLAS/LAPACK functions

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

    // Setup main app tests
    //const exe_unit_tests = b.addTest(.{
    //    .root_source_file = b.path("src/main.zig"),
    //    .target = target,
    //    .optimize = optimize,
    //});

    // Link libraries for main app tests
    //exe_unit_tests.linkSystemLibrary("c");
    //exe_unit_tests.linkSystemLibrary("c++");
    //exe_unit_tests.addIncludePath(b.path("mlx-c"));
    //exe_unit_tests.addIncludePath(b.path("mlx-c/mlx/c"));
    //exe_unit_tests.addIncludePath(b.path("wgpu-native/ffi"));
    //exe_unit_tests.addIncludePath(b.path("wgpu-native/ffi/webgpu-headers"));
    //exe_unit_tests.addIncludePath(b.path("tracy/public"));
    //exe_unit_tests.addObjectFile(b.path("mlx-c/build/libmlxc.a"));
    //exe_unit_tests.addObjectFile(b.path("mlx-c/build/_deps/mlx-build/libmlx.a"));
    //exe_unit_tests.addObjectFile(b.path("wgpu-native/target/debug/libwgpu_native.a"));
    //exe_unit_tests.linkFramework("Metal");
    //exe_unit_tests.linkFramework("Foundation");
    //exe_unit_tests.linkFramework("MetalPerformanceShaders");
    //exe_unit_tests.linkFramework("QuartzCore");
    //exe_unit_tests.linkFramework("Accelerate");

    //////////////////////////////////////////////////////
    // Setup vector comparison tests
    //const vec_tests = b.addTest(.{
    //    .root_source_file = b.path("src/vec_test.zig"),
    //    .target = target,
    //    .optimize = optimize,
    //});

    // Link libraries for vector tests
    //vec_tests.linkSystemLibrary("c");
    //vec_tests.linkSystemLibrary("c++");
    //vec_tests.addIncludePath(b.path("mlx-c"));
    //vec_tests.addIncludePath(b.path("mlx-c/mlx/c"));
    //vec_tests.addIncludePath(b.path("tracy/public"));
    //vec_tests.addObjectFile(b.path("mlx-c/build/libmlxc.a"));
    //vec_tests.addObjectFile(b.path("mlx-c/build/_deps/mlx-build/libmlx.a"));
    //vec_tests.linkFramework("Metal");
    //vec_tests.linkFramework("Foundation");
    //vec_tests.linkFramework("MetalPerformanceShaders");
    //vec_tests.linkFramework("QuartzCore");
    //vec_tests.linkFramework("Accelerate");

    // Create a run step for vector tests
    //const run_vec_tests = b.addRunArtifact(vec_tests);
    //const vec_test_step = b.step("test-vectors", "Run vector comparison tests");
    //vec_test_step.dependOn(&run_vec_tests.step);
    //////////////////////////////////////////////////////////

    // Main test step runs all unit tests
    //const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    //const test_step = b.step("test", "Run unit tests");
    //test_step.dependOn(&run_exe_unit_tests.step);
}
