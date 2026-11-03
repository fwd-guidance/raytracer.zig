const std = @import("std");

const Backend = enum { auto, metal, cpu, cuda };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    //const optimize = b.standardOptimizeOption(.{});

    if (!target.query.isNativeTriple()) {
        @panic("The mlx-c CMake build currently supports native targets only");
    }
    const os = target.result.os.tag;
    if (os != .macos and os != .linux) {
        @panic("This build currently supports native macOS and Linux hosts");
    }
    const requested_backend = b.option(Backend, "mlx-backend", "MLX backend: auto, metal, cpu, or cuda") orelse .auto;
    const backend: Backend = if (requested_backend == .auto)
        (if (os == .macos and target.result.cpu.arch == .aarch64) .metal else .cpu)
    else
        requested_backend;
    if (backend == .metal and (os != .macos or target.result.cpu.arch != .aarch64)) {
        @panic("The Metal backend requires Apple silicon running macOS");
    }
    if (backend == .cuda and os != .linux) {
        @panic("The CUDA backend requires a Linux host and NVIDIA CUDA/cuDNN");
    }
    const cpu = b.option(bool, "mlx-cpu", "Include the CPU backend (default: enabled except with Metal)") orelse (backend != .metal);
    if (backend == .cpu and !cpu) @panic("The CPU backend cannot be disabled in a CPU-only build");
    const metal = backend == .metal;

    const mlx_c = b.dependency("mlx_c", .{});
    // Keep CMake's generated files out of the fetched source directory.
    const configure_mlx = b.addSystemCommand(&.{ "cmake", "-S" });
    configure_mlx.addDirectoryArg2(mlx_c.path(""), .{});
    configure_mlx.addArg("-B");
    const mlx_build = configure_mlx.addOutputDirectoryArg2("mlx-build", .{ .make_absolute = true });
    configure_mlx.addArgs(&.{
        "-DCMAKE_BUILD_TYPE=Release",
        "-DBUILD_SHARED_LIBS=OFF",
        "-DMLX_C_BUILD_EXAMPLES=OFF",
        // mlx-c already disables MLX tests, examples,
        // benchmarks, and Python bindings in its CMake configuration.
        b.fmt("-DMLX_BUILD_METAL={s}", .{if (metal) "ON" else "OFF"}),
        b.fmt("-DMLX_BUILD_CPU={s}", .{if (cpu) "ON" else "OFF"}),
        "-DMLX_BUILD_SAFETENSORS=OFF",
        "-DMLX_BUILD_GGUF=OFF",
        "-DMLX_METAL_DEBUG=OFF",
        b.fmt("-DMLX_METAL_JIT={s}", .{if (metal) "ON" else "OFF"}),
    });
    if (backend == .cuda) configure_mlx.addArg("-DMLX_BUILD_CUDA=ON");
    if (os == .linux) configure_mlx.addArg("-DCMAKE_INSTALL_LIBDIR=lib");
    if (os == .macos and target.result.cpu.arch == .x86_64) configure_mlx.addArg("-DMLX_ENABLE_X64_MAC=ON");

    const build_mlx = b.addSystemCommand(&.{ "cmake", "--build" });
    build_mlx.addDirectoryArg2(mlx_build, .{});
    build_mlx.addArgs(&.{ "--config", "Release", "--parallel" });
    // Without an output argument, Run assumes side effects and executes every time.
    // Check mode caches successful builds for this pinned source/configuration.
    build_mlx.expectExitCode(0);

    const install_mlx = b.addSystemCommand(&.{ "cmake", "--install" });
    install_mlx.addDirectoryArg2(mlx_build, .{});
    install_mlx.addArgs(&.{ "--config", "Release", "--prefix" });
    const mlx_install = install_mlx.addOutputDirectoryArg2("mlx-install", .{ .make_absolute = true });
    install_mlx.step.dependOn(&build_mlx.step);

    const translate_mlx = b.addTranslateC(.{
        .root_source_file = mlx_c.path("mlx/c/mlx.h"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
    });
    translate_mlx.addIncludePath(mlx_c.path(""));
    const raw_mlx_module = translate_mlx.createModule();
    const generator_module = b.createModule(.{
        .root_source_file = b.path("tools/generate_mlx.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "mlx_c", .module = raw_mlx_module }},
    });
    const generator = b.addExecutable(.{
        .name = "generate-mlx",
        .root_module = generator_module,
    });
    const generate_mlx = b.addRunArtifact(generator);
    // Capturing an output makes this run cacheable. Consumers automatically
    // regenerate missing/stale bindings; unchanged builds reuse the output.
    const generated_mlx = generate_mlx.captureStdOut(.{ .basename = "mlx.zig" });
    const bindgen = b.step("bindgen", "Generate ergonomic Zig bindings for mlx-c");
    bindgen.dependOn(&generate_mlx.step);

    const mlx_module = b.createModule(.{
        .root_source_file = generated_mlx,
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "mlx_c", .module = raw_mlx_module }},
    });

    const binding_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/mlx_test.zig"),
        .target = target,
        .imports = &.{.{ .name = "mlx", .module = mlx_module }},
    }) });
    const generator_tests = b.addTest(.{ .root_module = generator_module });
    const test_step = b.step("test", "Test MLX binding generation");
    test_step.dependOn(&b.addRunArtifact(binding_tests).step);
    test_step.dependOn(&b.addRunArtifact(generator_tests).step);

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
    });

    // CMake performs the final C++ link using MLX's exported dependencies.
    // This avoids hardcoding BLAS/LAPACK, CUDA, or platform framework lists.
    const app_object = b.addObject(.{
        .name = "ray-tracer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .link_libc = true,
            .imports = &.{
                .{
                    .name = "mlx",
                    .module = mlx_module,
                },
                .{
                    .name = "c",
                    .module = translate_c.createModule(),
                },
            },
        }),
    });

    app_object.bundle_compiler_rt = true;
    app_object.root_module.addCSourceFile(.{
        .file = b.path("src/stb_image_impl.c"),
        .flags = &.{"-std=c99"},
    });

    app_object.root_module.addIncludePath(b.path("src"));

    const configure_link = b.addSystemCommand(&.{ "cmake", "-S" });
    configure_link.addDirectoryArg2(b.path("tools/link_native"), .{ .make_absolute = true });
    configure_link.addFileInput(b.path("tools/link_native/CMakeLists.txt"));
    configure_link.addArg("-B");
    const link_build = configure_link.addOutputDirectoryArg2("native-link", .{ .make_absolute = true });
    configure_link.addArg("-DCMAKE_BUILD_TYPE=Release");
    if (backend == .cuda) configure_link.addArg("-DRAYTRACER_CUDA=ON");
    if (os == .macos) {
        const minimum = target.result.os.version_range.semver.min;
        configure_link.addArg(b.fmt("-DCMAKE_OSX_DEPLOYMENT_TARGET={d}.{d}.{d}", .{ minimum.major, minimum.minor, minimum.patch }));
    }
    configure_link.addDirectoryArg2(mlx_install, .{ .prefix = "-DMLX_INSTALL_PREFIX=", .make_absolute = true });
    configure_link.addFileArg2(app_object.getEmittedBin(), .{ .prefix = "-DRAYTRACER_OBJECT=", .make_absolute = true });
    const link_app = b.addSystemCommand(&.{ "cmake", "--build" });
    link_app.addDirectoryArg2(link_build, .{});
    link_app.addArgs(&.{ "--config", "Release" });
    link_app.expectExitCode(0);
    const install_app = b.addInstallBinFile(link_build.path(b, "bin/ray-tracer"), "ray-tracer");
    install_app.step.dependOn(&link_app.step);
    b.getInstallStep().dependOn(&install_app.step);

    if (metal) {
        // Even with JIT, this release needs a reduced metallib beside the binary.
        const install_metallib = b.addInstallBinFile(mlx_install.path(b, "lib/mlx.metallib"), "mlx.metallib");
        b.getInstallStep().dependOn(&install_metallib.step);
    }

    const run_step = b.step("run", "Run the main app");
    const run_cmd = std.Build.Step.Run.create(b, "run ray-tracer");
    run_cmd.addFileArg2(.{ .relative = .{ .base = .install_bin, .sub_path = "ray-tracer" } }, .{ .make_absolute = true });
    run_cmd.step.dependOn(b.getInstallStep());
    run_step.dependOn(&run_cmd.step);

    run_cmd.addPassthruArgs();
}
