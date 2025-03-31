const rtw = @import("rtweekend.zig");
const wgpu = @import("wgpu");

const init = rtw.vec.init;
const Sphere = rtw.sphere.sphere;
const std = rtw.std;
const hittable_list = rtw.HittableList.HittableList;
const Camera = rtw.camera.Camera;
const Material = rtw.material.Material;
const AABB = @import("aabb.zig").AABB;
const BVHNode = @import("bvh.zig").BVHNode;

// Define a structure matching our WGSL shader's Camera struct
const GpuCamera = struct {
    center: @Vector(3, f32),
    pixel00_loc: @Vector(3, f32),
    pixel_delta_u: @Vector(3, f32),
    pixel_delta_v: @Vector(3, f32),
    defocus_disk_u: @Vector(3, f32),
    defocus_disk_v: @Vector(3, f32),
    defocus_angle: f32,
    u: @Vector(3, f32),
    v: @Vector(3, f32),
    w: @Vector(3, f32),
    samples_per_pixel: f32,
    max_depth: f32,
    aspect_ratio: f32,
    image_width: f32,
    image_height: f32,
    focus_dist: f32,
    _padding: [8]u32 = [_]u32{0} ** 8, // Padding to align to 16 bytes
};

// Define a structure matching our WGSL shader's MaterialType struct
const GpuMaterialType = struct {
    material_type: u32, // 0=lambertian, 1=metal, 2=dielectric
    albedo: @Vector(3, f32),
    fuzz: f32,
    refraction_index: f32,
    _padding: [3]u32 = [_]u32{0} ** 3, // Padding to align to 16 bytes
};

// Define a structure matching our WGSL shader's Sphere struct
const GpuSphere = struct {
    center: @Vector(3, f32),
    radius: f32,
    material: GpuMaterialType,
};

pub fn draw_ppm() !void {
    //allocator
    var gpa = std.heap.DebugAllocator(.{}){};
    //var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    // world
    var world = hittable_list.init(allocator);
    defer world.deinit();

    const material_ground = Material.lambertian(@Vector(3, f32){ 0.5, 0.5, 0.5 });
    //const material_center = Material.lambertian(@Vector(3, f32){ 0.1, 0.2, 0.5 });
    const material1 = Material.dielectric(1.50);
    //const material_bubble = Material.dielectric(1.00 / 1.50);
    //const material_right = Material.metal(@Vector(3, f32){ 0.8, 0.6, 0.2 }, 1.0);
    const material2 = Material.lambertian(@Vector(3, f32){ 0.4, 0.2, 0.1 });
    const material3 = Material.metal(@Vector(3, f32){ 0.7, 0.6, 0.5 }, 0.0);

    var a: f32 = -11;
    while (a < 11) : (a += 1) {
        var b: f32 = -11;
        while (b < 11) : (b += 1) {
            const choose_mat = rtw.random_double();

            const center: @Vector(3, f32) = @Vector(3, f32){ a + 0.9 * rtw.random_double(), 0.2, b + 0.9 * rtw.random_double() };
            if (try rtw.vec.magnitude(center - @Vector(3, f32){ 4.0, 0.2, 0.0 }) > 0.9) {
                if (choose_mat < 0.8) {
                    const albedo = (rtw.vec.random_vec_range(0.0, 1.0) * rtw.vec.random_vec_range(0.0, 1.0));
                    const sphere_material = Material.lambertian(albedo);
                    _ = try world.add(Sphere.init(center, 0.2, sphere_material));
                } else if (choose_mat < 0.95) {
                    const albedo = rtw.vec.random_vec_range(0.5, 1.0);
                    const fuzz = rtw.random_double_range(0, 0.5);
                    const sphere_material = Material.metal(albedo, fuzz);
                    _ = try world.add(Sphere.init(center, 0.2, sphere_material));
                } else {
                    const sphere_material = Material.dielectric(1.5);
                    _ = try world.add(Sphere.init(center, 0.2, sphere_material));
                }
            }
        }
    }

    _ = try world.add(Sphere.init(init(0, 1, 0), 1.0, material1));
    _ = try world.add(Sphere.init(init(-4, 1, 0), 1.0, material2));
    _ = try world.add(Sphere.init(init(4, 1, 0), 1.0, material3));
    _ = try world.add(Sphere.init(init(0.0, -1000, 0), 1000, material_ground));

    try world.buildBVH();

    // Camera
    var cam: Camera = undefined;
    cam.aspect_ratio = 16.0 / 9.0;
    cam.image_width = 400;
    cam.samples_per_pixel = 10;
    cam.max_depth = 5;

    cam.vfov = 20;
    cam.lookfrom = @Vector(3, f32){ 13, 2, 3 };
    cam.lookat = @Vector(3, f32){ 0, 0, 0 };
    cam.vup = @Vector(3, f32){ 0, 1, 0 };
    cam.defocus_angle = 0.6;
    cam.focus_dist = 10.0;

    try cam.render(&world);
}

pub fn main() !void {
    try gpu_main();
}

//const std = @import("std");
//const wgpu = @import("wgpu");
const bmp = @import("bmp.zig");

const output_extent = wgpu.Extent3D{
    .width = 640,
    .height = 480,
    .depth_or_array_layers = 1,
};
const output_bytes_per_row = 4 * output_extent.width;
const output_size = output_bytes_per_row * output_extent.height;

// fn handle_buffer_map(status: wgpu.BufferMapAsyncStatus, _: ?*anyopaque) callconv(.C) void {
//     std.log.info("buffer_map status={x:.8}\n", .{@intFromEnum(status)});
// }

// Based off of headless triangle example from https://github.com/eliemichel/LearnWebGPU-Code/tree/step030-headless

pub fn triangle_main() !void {
    const instance = wgpu.Instance.create(null).?;
    defer instance.release();

    const adapter_request = instance.requestAdapterSync(&wgpu.RequestAdapterOptions{});
    const adapter = switch (adapter_request.status) {
        .success => adapter_request.adapter.?,
        else => return error.NoAdapter,
    };
    defer adapter.release();

    const device_request = adapter.requestDeviceSync(&wgpu.DeviceDescriptor{
        .required_limits = null,
    });
    const device = switch (device_request.status) {
        .success => device_request.device.?,
        else => return error.NoDevice,
    };
    defer device.release();

    const queue = device.getQueue().?;
    defer queue.release();

    const swap_chain_format = wgpu.TextureFormat.bgra8_unorm_srgb;

    const target_texture = device.createTexture(&wgpu.TextureDescriptor{
        .label = "Render texture",
        .size = output_extent,
        .format = swap_chain_format,
        .usage = wgpu.TextureUsage.render_attachment | wgpu.TextureUsage.copy_src,
    }).?;
    defer target_texture.release();

    const target_texture_view = target_texture.createView(&wgpu.TextureViewDescriptor{
        .label = "Render texture view",
        .mip_level_count = 1,
        .array_layer_count = 1,
    }).?;

    const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .code = @embedFile("./shader.wgsl"),
    })).?;
    defer shader_module.release();

    const staging_buffer = device.createBuffer(&wgpu.BufferDescriptor{
        .label = "staging_buffer",
        .usage = wgpu.BufferUsage.map_read | wgpu.BufferUsage.copy_dst,
        .size = output_size,
        .mapped_at_creation = @as(u32, @intFromBool(false)),
    }).?;
    defer staging_buffer.release();

    const color_targets = &[_]wgpu.ColorTargetState{
        wgpu.ColorTargetState{
            .format = swap_chain_format,
            .blend = &wgpu.BlendState{
                .color = wgpu.BlendComponent{
                    .operation = .add,
                    .src_factor = .src_alpha,
                    .dst_factor = .one_minus_src_alpha,
                },
                .alpha = wgpu.BlendComponent{
                    .operation = .add,
                    .src_factor = .zero,
                    .dst_factor = .one,
                },
            },
        },
    };

    const pipeline = device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .vertex = wgpu.VertexState{
            .module = shader_module,
            .entry_point = "vs_main",
        },
        .primitive = wgpu.PrimitiveState{},
        .fragment = &wgpu.FragmentState{ .module = shader_module, .entry_point = "fs_main", .target_count = color_targets.len, .targets = color_targets.ptr },
        .multisample = wgpu.MultisampleState{},
    }).?;
    defer pipeline.release();

    { // Mock main "loop"
        const next_texture = target_texture_view;

        const encoder = device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
            .label = "Command Encoder",
        }).?;
        defer encoder.release();

        const color_attachments = &[_]wgpu.ColorAttachment{wgpu.ColorAttachment{
            .view = next_texture,
            .clear_value = wgpu.Color{},
        }};
        const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .color_attachment_count = color_attachments.len,
            .color_attachments = color_attachments.ptr,
        }).?;

        render_pass.setPipeline(pipeline);
        render_pass.draw(3, 1, 0, 0);
        render_pass.end();

        // The render pass has to be released after .end() or otherwise we'll crash on queue.submit
        // https://github.com/gfx-rs/wgpu-native/issues/412#issuecomment-2311719154
        render_pass.release();

        defer next_texture.release();

        const img_copy_src = wgpu.ImageCopyTexture{
            .origin = wgpu.Origin3D{},
            .texture = target_texture,
        };
        const img_copy_dst = wgpu.ImageCopyBuffer{
            .layout = wgpu.TextureDataLayout{
                .bytes_per_row = output_bytes_per_row,
                .rows_per_image = output_extent.height,
            },
            .buffer = staging_buffer,
        };

        encoder.copyTextureToBuffer(&img_copy_src, &img_copy_dst, &output_extent);

        const command_buffer = encoder.finish(&wgpu.CommandBufferDescriptor{
            .label = "Command Buffer",
        }).?;
        defer command_buffer.release();

        queue.submit(&[_]*const wgpu.CommandBuffer{command_buffer});

        staging_buffer.mapAsync(wgpu.MapMode.read, 0, output_size, handle_buffer_map, null);
        _ = device.poll(true, null);

        const buf: [*]u8 = @ptrCast(@alignCast(staging_buffer.getMappedRange(0, output_size).?));
        defer staging_buffer.unmap();

        const output = buf[0..output_size].*;
        std.debug.print("{}", .{output.len});
        var i: usize = 0;
        while (i < output.len) : (i += 1) {
            if (output[i] != 0) {
                std.debug.print("{}\n", .{output[i]});
            }
        }
        //try bmp.write24BitBMP("examples/output/triangle.bmp", output_extent.width, output_extent.height, output);
    }
}

pub fn gpu_main() !void {
    const numbers = [10]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    const numbers_size = @sizeOf(@TypeOf(numbers));
    //const numbers_size = 4;
    const numbers_length = numbers_size / @sizeOf(u32);

    const instance = wgpu.Instance.create(null).?;
    defer instance.release();

    const adapter_request = instance.requestAdapterSync(&wgpu.RequestAdapterOptions{});
    const adapter = switch (adapter_request.status) {
        .success => adapter_request.adapter.?,
        else => return error.NoAdapter,
    };
    defer adapter.release();

    const device_request = adapter.requestDeviceSync(&wgpu.DeviceDescriptor{
        .required_limits = null,
    });
    const device = switch (device_request.status) {
        .success => device_request.device.?,
        else => return error.NoDevice,
    };
    defer device.release();

    const queue = device.getQueue().?;
    defer queue.release();

    const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .code = @embedFile("./shader.wgsl"),
    })).?;
    defer shader_module.release();

    const staging_buffer = device.createBuffer(&wgpu.BufferDescriptor{
        .label = "staging_buffer",
        .usage = wgpu.BufferUsage.map_read | wgpu.BufferUsage.copy_dst,
        .size = numbers_size,
        .mapped_at_creation = @as(u32, @intFromBool(false)),
    }).?;
    defer staging_buffer.release();

    const storage_buffer = device.createBuffer(&wgpu.BufferDescriptor{
        .label = "storage_buffer",
        .usage = wgpu.BufferUsage.storage | wgpu.BufferUsage.copy_dst | wgpu.BufferUsage.copy_src,
        .size = numbers_size,
        .mapped_at_creation = @as(u32, @intFromBool(false)),
    }).?;
    defer storage_buffer.release();

    const compute_pipeline = device.createComputePipeline(&wgpu.ComputePipelineDescriptor{
        .label = "compute_pipeline",
        .compute = wgpu.ProgrammableStageDescriptor{
            .module = shader_module,
            .entry_point = "main",
        },
    }).?;
    defer compute_pipeline.release();

    const bind_group_layout = compute_pipeline.getBindGroupLayout(0).?;
    defer bind_group_layout.release();

    const bind_group = device.createBindGroup(&wgpu.BindGroupDescriptor{
        .label = "bind_group",
        .layout = bind_group_layout,
        .entry_count = 1,
        .entries = &[_]wgpu.BindGroupEntry{
            wgpu.BindGroupEntry{
                .binding = 0,
                .buffer = storage_buffer,
                .offset = 0,
                .size = numbers_size,
            },
        },
    }).?;
    defer bind_group.release();

    const command_encoder = device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
        .label = "command_encoder",
    }).?;
    defer command_encoder.release();

    //     // First, run the compute shader
    //     const compute_encoder = device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
    //         .label = "Compute Command Encoder",
    //     }).?;
    //     defer compute_encoder.release();

    //     const compute_pass = compute_encoder.beginComputePass(&wgpu.ComputePassDescriptor{}).?;
    //     compute_pass.setPipeline(compute_pipeline);
    //     compute_pass.setBindGroup(0, bind_group, 0, null);

    const compute_pass_encoder = command_encoder.beginComputePass(&wgpu.ComputePassDescriptor{ .label = "compute_pass" }).?;
    defer compute_pass_encoder.release();

    compute_pass_encoder.setPipeline(compute_pipeline);
    compute_pass_encoder.setBindGroup(0, bind_group, 0, null);
    compute_pass_encoder.dispatchWorkgroups(numbers_length, 1, 1);
    compute_pass_encoder.end();
    compute_pass_encoder.release();

    command_encoder.copyBufferToBuffer(storage_buffer, 0, staging_buffer, 0, numbers_size);

    const command_buffer = command_encoder.finish(&wgpu.CommandBufferDescriptor{
        .label = "command_buffer",
    }).?;
    defer command_buffer.release();

    queue.writeBuffer(storage_buffer, 0, &numbers, numbers_size);
    queue.submit(&[_]*const wgpu.CommandBuffer{command_buffer});

    buffer_map_done = false;
    staging_buffer.mapAsync(wgpu.MapMode.read, 0, numbers_size, handle_buffer_map, null);
    _ = device.poll(true, null);

    //     // Map the staging buffer to read back the result
    //     // buffer_map_done = false;
    //     staging_buffer.mapAsync(wgpu.MapMode.read, 0, output_size, handle_buffer_map, null);
    //     _ = device.poll(true, null);

    //     // Wait for the mapping to complete with timeout
    var timeout_counter: u32 = 0;
    const max_timeout = 1000; // Try up to 1000 iterations

    while (!buffer_map_done and timeout_counter < max_timeout) {
        _ = device.poll(true, null);
        timeout_counter += 1;
        if (timeout_counter % 100 == 0) {
            std.debug.print("Waiting for buffer mapping... {d}/{d}\n", .{ timeout_counter, max_timeout });
        }
    }

    if (!buffer_map_done) {
        std.debug.print("Buffer mapping timed out!\n", .{});
        return;
    }

    std.debug.print("Buffer mapped successfully after {d} iterations\n", .{timeout_counter});
    const buf: [*]u8 = @ptrCast(@alignCast(staging_buffer.getMappedRange(0, numbers_size).?));

    defer staging_buffer.unmap();
    std.debug.print("{any}\n", .{buf});
    const output = buf[0..numbers_size].*;
    std.debug.print("{any}\n", .{output});

    //queue.QueueWriteBuffer(storage_buffer, 0, &numbers, numbers_size);
    //queue.QueueSubmit(1, &command_buffer);

    //staging_buffer.BufferMapAsync()

}

// const output_extent = wgpu.Extent3D{
//     .width = 1280,
//     .height = 720,
//     .depth_or_array_layers = 1,
// };
// const output_bytes_per_row = 4 * output_extent.width;
// const output_size = output_bytes_per_row * output_extent.height;

// fn handle_buffer_map(status: wgpu.BufferMapAsyncStatus, _: ?*anyopaque) callconv(.C) void {
//     std.log.info("buffer_map status={x:.8}\n", .{@intFromEnum(status)});
// }

//This callback is called when the buffer mapping is complete
var buffer_map_done: bool = false;

fn handle_buffer_map(status: wgpu.BufferMapAsyncStatus, _: ?*anyopaque) callconv(.C) void {
    std.debug.print("Buffer map callback triggered with status: {s}\n", .{@tagName(status)});

    if (status == .success) {
        std.debug.print("Buffer mapped successfully!\n", .{});
        buffer_map_done = true;
    } else {
        std.debug.print("Buffer mapping failed with status: {s}\n", .{@tagName(status)});
        // Set to true anyway so we don't get stuck in a loop
        buffer_map_done = true;
    }
}

// Get the appropriate enum value for material types
fn getMaterialTypeEnum(material: Material) u32 {
    return switch (material) {
        .Lambertian => 0,
        .Metal => 1,
        .Dielectric => 2,
    };
}

// Convert a Sphere to a GpuSphere
fn toGpuSphere(sphere: Sphere) GpuSphere {
    var gpu_material = GpuMaterialType{
        .material_type = getMaterialTypeEnum(sphere.mat),
        .albedo = @Vector(3, f32){ 1.0, 1.0, 1.0 }, // Default white
        .fuzz = 0.0,
        .refraction_index = 1.0,
    };

    // Set the appropriate material properties based on the material type
    switch (sphere.mat) {
        .Lambertian => |l| gpu_material.albedo = l.albedo,
        .Metal => |m| {
            gpu_material.albedo = m.albedo;
            gpu_material.fuzz = m.fuzz;
        },
        .Dielectric => |d| {
            gpu_material.refraction_index = d.refraction_index;
            // Dielectrics typically have white albedo (for when they reflect)
            gpu_material.albedo = @Vector(3, f32){ 1.0, 1.0, 1.0 };
        },
    }

    return GpuSphere{
        .center = sphere.center,
        .radius = sphere.radius,
        .material = gpu_material,
    };
}

// // Function to write a PPM file from a buffer
fn writeToPpm(width: u32, height: u32, buffer: []u8) !void {
    const stdout = std.io.getStdOut().writer();

    // P3 format (ASCII)
    try stdout.print("P3\n{d} {d}\n255\n", .{ width, height });

    // Write each pixel's RGB values
    var total_written: usize = 0;

    for (0..height) |y| {
        for (0..width) |x| {
            const index = (y * width + x) * 4;
            if (index + 2 >= buffer.len) break;

            // Shader output is in RGBA format
            const r = buffer[index + 0];
            const g = buffer[index + 1];
            const b = buffer[index + 2];

            try stdout.print("{d} {d} {d}\n", .{ r, g, b });
            total_written += 1;
        }
    }

    std.debug.print("PPM output: Wrote {d} of {d} expected pixels\n", .{ total_written, width * height });
}

// pub fn gpu_main() !void {
//     // Setup allocator
//     var gpa = std.heap.DebugAllocator(.{}){};
//     var arena = std.heap.ArenaAllocator.init(gpa.allocator());
//     defer arena.deinit();
//     const allocator = arena.allocator();

//     std.debug.print("Initializing GPU ray tracer...\n", .{});

//     // Create world and populate with spheres
//     var world = hittable_list.init(allocator);
//     defer world.deinit();

//     const material_ground = Material.lambertian(@Vector(3, f32){ 0.5, 0.5, 0.5 });
//     const material1 = Material.dielectric(1.50);
//     const material2 = Material.lambertian(@Vector(3, f32){ 0.4, 0.2, 0.1 });
//     const material3 = Material.metal(@Vector(3, f32){ 0.7, 0.6, 0.5 }, 0.0);

//     // var a: f32 = -11;
//     // while (a < 11) : (a += 1) {
//     //     var b: f32 = -11;
//     //     while (b < 11) : (b += 1) {
//     //         const choose_mat = rtw.random_double();

//     //         const center: @Vector(3, f32) = @Vector(3, f32){ a + 0.9 * rtw.random_double(), 0.2, b + 0.9 * rtw.random_double() };
//     //         if (try rtw.vec.magnitude(center - @Vector(3, f32){ 4.0, 0.2, 0.0 }) > 0.9) {
//     //             if (choose_mat < 0.8) {
//     //                 const albedo = (rtw.vec.random_vec_range(0.0, 1.0) * rtw.vec.random_vec_range(0.0, 1.0));
//     //                 const sphere_material = Material.lambertian(albedo);
//     //                 _ = try world.add(Sphere.init(center, 0.2, sphere_material));
//     //             } else if (choose_mat < 0.95) {
//     //                 const albedo = rtw.vec.random_vec_range(0.5, 1.0);
//     //                 const fuzz = rtw.random_double_range(0, 0.5);
//     //                 const sphere_material = Material.metal(albedo, fuzz);
//     //                 _ = try world.add(Sphere.init(center, 0.2, sphere_material));
//     //             } else {
//     //                 const sphere_material = Material.dielectric(1.5);
//     //                 _ = try world.add(Sphere.init(center, 0.2, sphere_material));
//     //             }
//     //         }
//     //     }
//     // }

//     _ = try world.add(Sphere.init(init(0, 1, 0), 1.0, material1));
//     _ = try world.add(Sphere.init(init(-4, 1, 0), 1.0, material2));
//     _ = try world.add(Sphere.init(init(4, 1, 0), 1.0, material3));
//     _ = try world.add(Sphere.init(init(0.0, -1000, 0), 1000, material_ground));

//     try world.buildBVH();

//     std.debug.print("Created {d} spheres for GPU rendering\n", .{world.objects.items.len});

//     // Convert all spheres to GPU format
//     var gpu_spheres = try allocator.alloc(GpuSphere, world.objects.items.len);
//     defer allocator.free(gpu_spheres);

//     std.debug.print("Converting spheres to GPU format...\n", .{});
//     for (world.objects.items, 0..) |sphere, i| {
//         gpu_spheres[i] = toGpuSphere(sphere);
//     }

//     // Setup camera
//     var cam = Camera{
//         .aspect_ratio = @as(f32, @floatFromInt(output_extent.width)) / @as(f32, @floatFromInt(output_extent.height)),
//         .image_width = @floatFromInt(output_extent.width),
//         .image_height = @floatFromInt(output_extent.height),
//         .samples_per_pixel = 5, // Start with a lower sample count for faster debug renders
//         .max_depth = 5,
//         .vfov = 20,
//         .lookfrom = @Vector(3, f32){ 13, 2, 3 },
//         .lookat = @Vector(3, f32){ 0, 0, 0 },
//         .vup = @Vector(3, f32){ 0, 1, 0 },
//         .defocus_angle = 0.6,
//         .focus_dist = 10.0,
//         .center = undefined,
//         .pixel00_loc = undefined,
//         .pixel_delta_u = undefined,
//         .pixel_delta_v = undefined,
//         .pixel_samples_scale = undefined,
//         .u = undefined,
//         .v = undefined,
//         .w = undefined,
//         .defocus_disk_u = undefined,
//         .defocus_disk_v = undefined,
//         .mutex = undefined,
//         .num_threads = 1,
//     };

//     // Initialize camera (but don't render)
//     cam.initialize();

//     // Create a GpuCamera struct for the compute shader
//     var gpu_camera = GpuCamera{
//         .center = cam.center,
//         .pixel00_loc = cam.pixel00_loc,
//         .pixel_delta_u = cam.pixel_delta_u,
//         .pixel_delta_v = cam.pixel_delta_v,
//         .defocus_disk_u = cam.defocus_disk_u,
//         .defocus_disk_v = cam.defocus_disk_v,
//         .defocus_angle = cam.defocus_angle,
//         .u = cam.u,
//         .v = cam.v,
//         .w = cam.w,
//         .samples_per_pixel = cam.samples_per_pixel,
//         .max_depth = cam.max_depth,
//         .aspect_ratio = cam.aspect_ratio,
//         .image_width = cam.image_width,
//         .image_height = cam.image_height,
//         .focus_dist = cam.focus_dist,
//     };

//     // Initialize WebGPU
//     std.debug.print("Initializing WebGPU...\n", .{});
//     const instance = wgpu.Instance.create(null).?;
//     defer instance.release();

//     const adapter_request = instance.requestAdapterSync(&wgpu.RequestAdapterOptions{});
//     const adapter = switch (adapter_request.status) {
//         .success => adapter_request.adapter.?,
//         else => return error.NoAdapter,
//     };
//     defer adapter.release();

//     // Simply use default limits to ensure device creation works
//     const device_request = adapter.requestDeviceSync(&wgpu.DeviceDescriptor{
//         .required_limits = null, // Use default limits
//     });
//     const device = switch (device_request.status) {
//         .success => device_request.device.?,
//         else => return error.NoDevice,
//     };
//     defer device.release();

//     const queue = device.getQueue().?;
//     defer queue.release();

//     // Create the compute shader module
//     std.debug.print("Creating compute shader...\n", .{});
//     const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
//         .code = @embedFile("./shader.wgsl"),
//     })).?;
//     defer shader_module.release();

//     // Create uniform buffer for camera settings
//     const camera_buffer_size = @sizeOf(GpuCamera);
//     const camera_buffer = device.createBuffer(&wgpu.BufferDescriptor{
//         .label = "Camera Uniform Buffer",
//         .size = camera_buffer_size,
//         .usage = wgpu.BufferUsage.uniform | wgpu.BufferUsage.copy_dst,
//         .mapped_at_creation = @as(u32, @intFromBool(false)),
//     }).?;
//     defer camera_buffer.release();

//     // Create storage buffer for spheres
//     const spheres_buffer_size = @sizeOf(GpuSphere) * world.objects.items.len;
//     const spheres_buffer = device.createBuffer(&wgpu.BufferDescriptor{
//         .label = "Spheres Storage Buffer",
//         .size = spheres_buffer_size,
//         .usage = wgpu.BufferUsage.storage | wgpu.BufferUsage.copy_dst,
//         .mapped_at_creation = @as(u32, @intFromBool(false)),
//     }).?;
//     defer spheres_buffer.release();

//     // Create storage buffer for output results
//     const result_buffer_size = output_extent.width * output_extent.height * @sizeOf(f32) * 4; // vec4f per pixel
//     const result_buffer = device.createBuffer(&wgpu.BufferDescriptor{
//         .label = "Result Storage Buffer",
//         .size = result_buffer_size,
//         .usage = wgpu.BufferUsage.storage | wgpu.BufferUsage.copy_src,
//         .mapped_at_creation = @as(u32, @intFromBool(false)),
//     }).?;
//     defer result_buffer.release();

//     // Create a staging buffer for reading back the result
//     const staging_buffer = device.createBuffer(&wgpu.BufferDescriptor{
//         .label = "Staging Buffer",
//         .size = output_size,
//         .usage = wgpu.BufferUsage.map_read | wgpu.BufferUsage.copy_dst,
//         .mapped_at_creation = @as(u32, @intFromBool(false)),
//     }).?;
//     defer staging_buffer.release();

//     // Create the compute pipeline layout
//     const bind_group_layout = device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
//         .label = "Bind Group Layout",
//         .entry_count = 3,
//         .entries = &[_]wgpu.BindGroupLayoutEntry{
//             wgpu.BindGroupLayoutEntry{
//                 .binding = 0,
//                 .visibility = wgpu.ShaderStage.compute,
//                 .buffer = wgpu.BufferBindingLayout{
//                     .type = .uniform,
//                     .min_binding_size = camera_buffer_size,
//                 },
//                 .sampler = undefined,
//                 .storage_texture = undefined,
//                 .texture = undefined,
//             },
//             wgpu.BindGroupLayoutEntry{
//                 .binding = 1,
//                 .visibility = wgpu.ShaderStage.compute,
//                 .buffer = wgpu.BufferBindingLayout{
//                     .type = .read_only_storage,
//                     .min_binding_size = spheres_buffer_size,
//                 },
//                 .sampler = undefined,
//                 .storage_texture = undefined,
//                 .texture = undefined,
//             },
//             wgpu.BindGroupLayoutEntry{
//                 .binding = 2,
//                 .visibility = wgpu.ShaderStage.compute,
//                 .buffer = wgpu.BufferBindingLayout{
//                     .type = .storage,
//                     .min_binding_size = result_buffer_size,
//                 },
//                 .sampler = undefined,
//                 .storage_texture = undefined,
//                 .texture = undefined,
//             },
//         },
//     }).?;
//     defer bind_group_layout.release();

//     const bind_group_layout_slice = [_]*wgpu.BindGroupLayout{bind_group_layout};
//     const pipeline_layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
//         .label = "Compute Pipeline Layout",
//         .bind_group_layout_count = 1,
//         .bind_group_layouts = &bind_group_layout_slice,
//     }).?;
//     defer pipeline_layout.release();

//     // Create the compute pipeline
//     const compute_pipeline = device.createComputePipeline(&wgpu.ComputePipelineDescriptor{
//         .label = "Ray Tracing Compute Pipeline",
//         .layout = pipeline_layout,
//         .compute = wgpu.ProgrammableStageDescriptor{
//             .module = shader_module,
//             .entry_point = "cs_main",
//         },
//     }).?;
//     defer compute_pipeline.release();

//     // Create the bind group
//     const bind_group = device.createBindGroup(&wgpu.BindGroupDescriptor{
//         .label = "Ray Tracing Bind Group",
//         .layout = bind_group_layout,
//         .entry_count = 3,
//         .entries = &[_]wgpu.BindGroupEntry{
//             wgpu.BindGroupEntry{
//                 .binding = 0,
//                 .buffer = camera_buffer,
//                 .size = camera_buffer_size,
//                 .offset = 0,
//                 .sampler = undefined,
//                 .texture_view = undefined,
//             },
//             wgpu.BindGroupEntry{
//                 .binding = 1,
//                 .buffer = spheres_buffer,
//                 .size = spheres_buffer_size,
//                 .offset = 0,
//                 .sampler = undefined,
//                 .texture_view = undefined,
//             },
//             wgpu.BindGroupEntry{
//                 .binding = 2,
//                 .buffer = result_buffer,
//                 .size = result_buffer_size,
//                 .offset = 0,
//                 .sampler = undefined,
//                 .texture_view = undefined,
//             },
//         },
//     }).?;
//     defer bind_group.release();

//     // Upload camera data
//     queue.writeBuffer(camera_buffer, 0, &gpu_camera, @sizeOf(GpuCamera));

//     // Upload spheres data
//     queue.writeBuffer(spheres_buffer, 0, gpu_spheres.ptr, spheres_buffer_size);

//     // Create and submit compute command
//     std.debug.print("Dispatching compute shader for ray tracing...\n", .{});

//     // First, run the compute shader
//     const compute_encoder = device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
//         .label = "Compute Command Encoder",
//     }).?;
//     defer compute_encoder.release();

//     const compute_pass = compute_encoder.beginComputePass(&wgpu.ComputePassDescriptor{}).?;
//     compute_pass.setPipeline(compute_pipeline);
//     compute_pass.setBindGroup(0, bind_group, 0, null);

//     // Dispatch workgroups - make sure to cover the entire output
//     const work_group_size = 8; // Must match workgroup_size in shader
//     const width_groups = (output_extent.width + work_group_size - 1) / work_group_size;
//     const height_groups = (output_extent.height + work_group_size - 1) / work_group_size;
//     compute_pass.dispatchWorkgroups(width_groups, height_groups, 1);
//     compute_pass.end();
//     compute_pass.release();

//     const compute_commands = compute_encoder.finish(&wgpu.CommandBufferDescriptor{
//         .label = "Compute Commands",
//     }).?;

//     // Submit the compute commands and wait for completion
//     queue.submit(&[_]*wgpu.CommandBuffer{compute_commands});
//     _ = device.poll(true, null);
//     compute_commands.release();

//     // Now create a copy command to get the results
//     const copy_encoder = device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
//         .label = "Copy Command Encoder",
//     }).?;
//     defer copy_encoder.release();

//     // Copy the result to the staging buffer
//     copy_encoder.copyBufferToBuffer(result_buffer, 0, staging_buffer, 0, output_size);

//     const copy_commands = copy_encoder.finish(&wgpu.CommandBufferDescriptor{
//         .label = "Copy Commands",
//     }).?;

//     // Submit the copy commands
//     queue.submit(&[_]*wgpu.CommandBuffer{copy_commands});
//     copy_commands.release();

//     // Map the staging buffer to read back the result
//     // buffer_map_done = false;
//     staging_buffer.mapAsync(wgpu.MapMode.read, 0, output_size, handle_buffer_map, null);
//     _ = device.poll(true, null);

//     // Wait for the mapping to complete with timeout
//     // var timeout_counter: u32 = 0;
//     // const max_timeout = 1000; // Try up to 1000 iterations

//     // while (!buffer_map_done and timeout_counter < max_timeout) {
//     //     _ = device.poll(true, null);
//     //     timeout_counter += 1;
//     //     if (timeout_counter % 100 == 0) {
//     //         std.debug.print("Waiting for buffer mapping... {d}/{d}\n", .{ timeout_counter, max_timeout });
//     //     }
//     // }

//     // if (!buffer_map_done) {
//     //     std.debug.print("Buffer mapping timed out!\n", .{});
//     //     return;
//     // }

//     // std.debug.print("Buffer mapped successfully after {d} iterations\n", .{timeout_counter});

//     // Get a pointer to the mapped data
//     // const mapped_ptr = staging_buffer.getMappedRange(0, output_size) orelse {
//     //     std.debug.print("Failed to get mapped range\n", .{});
//     //     return;
//     // };

//     // std.debug.print("Got mapped range pointer: {*}\n", .{mapped_ptr});
//     // Allocate memory for the output buffer and copy data
//     // const output_buffer = try allocator.alloc(u8, output_size);
//     // defer allocator.free(output_buffer);

//     // Safety measure - fill buffer with a known pattern first
//     // @memset(output_buffer, 255); // Fill with all 255 (white) first

//     // std.debug.print("\n----------OUTPUT BUFFER-------------\n", .{});
//     // std.debug.print("{any}", .{output_buffer[0]});
//     // std.debug.print("\n----------HERE-------------\n", .{});

//     // Convert to a byte slice for copying
//     // const mapped_range = @as([*]const u8, @ptrCast(mapped_ptr))[0..output_size];

//     // std.debug.print("\n----------MAPPED_RANGE-------------\n", .{});
//     // std.debug.print("{any}", .{mapped_range[0]});
//     // std.debug.print("\n----------HERE-------------\n", .{});
//     // Copy the GPU output data to our local buffer
//     //@memcpy(output_buffer, mapped_range);
//     const buf: [*]u8 = @ptrCast(@alignCast(staging_buffer.getMappedRange(0, output_size).?));
//     // Unmap the buffer
//     defer staging_buffer.unmap();

//     std.debug.print("\nRender complete! Writing output...\n", .{});
//     const output = buf[0..output_size].*;

//     std.debug.print("\n----------OUTPUT-------------\n", .{});
//     std.debug.print("{any}", .{output[0]});
//     std.debug.print("\n----------HERE-------------\n", .{});

//     // Debug: Check if buffer has non-zero values
//     // var non_zero_count: usize = 0;
//     // for (output_buffer, 0..) |byte, i| {
//     //     if (byte > 0) {
//     //         non_zero_count += 1;
//     //         if (non_zero_count <= 10) {
//     //             std.debug.print("Non-zero byte at {d}: {d}\n", .{ i, byte });
//     //         }
//     //     }
//     // }

//     // std.debug.print("Buffer has {d} non-zero bytes out of {d}\n", .{ non_zero_count, output_size });

//     // Create a new debug file with raw bytes
//     //const file = try std.fs.cwd().createFile("debug_output.bin", .{});
//     //defer file.close();
//     //_ = try file.writeAll(output_buffer);
//     //std.debug.print("Wrote debug binary file to debug_output.bin\n", .{});

//     // Fill buffer with known pattern to verify PPM writing
//     // for (0..@intCast(output_extent.height)) |y| {
//     //     for (0..@intCast(output_extent.width)) |x| {
//     //         const index = (y * output_extent.width + x) * 4;
//     //         if (index + 3 < output_buffer.len) {
//     //             // Create a simple gradient pattern
//     //             const r: u8 = @truncate(@as(u8, @intCast(x * 255 / output_extent.width)));
//     //             const g: u8 = @truncate(@as(u8, @intCast(y * 255 / output_extent.height)));
//     //             const b: u8 = 255 - r;

//     //             output_buffer[index + 0] = r; // R
//     //             output_buffer[index + 1] = g; // G
//     //             output_buffer[index + 2] = b; // B
//     //             output_buffer[index + 3] = 255; // A
//     //         }
//     //     }
//     // }
//     //std.debug.print("{any}\n", .{output_buffer[0]});

//     // // Output to PPM format (should show a gradient pattern now)
//     // try writeToPpm(output_extent.width, output_extent.height, output_buffer);

//     std.debug.print("Done!\n", .{});
// }
