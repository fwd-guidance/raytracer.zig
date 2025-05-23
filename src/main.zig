const rtw = @import("rtweekend.zig");
const std = rtw.std;
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const stime = sokol.time;
const render_setup = @import("render_setup.zig");
const shd = @import("shader.glsl.zig");

// Import ray tracer components
const Sphere = rtw.sphere.sphere;
const HittableList = rtw.HittableList.HittableList;
const Camera = rtw.camera.Camera;
const Material = rtw.material.Material;
const init = rtw.vec.init;
const hittable_list = rtw.HittableList.HittableList;

pub fn draw_ppm() !void {
    //allocator
    var gpa = std.heap.DebugAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    // world
    var world = hittable_list.init(allocator);
    defer world.deinit();

    const material_ground = Material.lambertian(@Vector(3, f32){ 0.5, 0.5, 0.5 });
    const material1 = Material.dielectric(1.50);
    const material2 = Material.lambertian(@Vector(3, f32){ 0.4, 0.2, 0.1 });
    const material3 = Material.metal(@Vector(3, f32){ 0.7, 0.6, 0.5 }, 0.0);

    var a: f32 = -11;
    while (a < 11) : (a += 1) {
        var b: f32 = -11;
        while (b < 11) : (b += 1) {
            const choose_mat = rtw.random_double();
            const center: @Vector(3, f32) = @Vector(3, f32){ a + 0.9 * rtw.random_double(), 0.2, b + 0.9 * rtw.random_double() };
            std.debug.print("CPU LOOP: {any}\n", .{center});
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

    var cam: Camera = undefined;
    cam.aspect_ratio = 16.0 / 16.0;
    cam.image_width = 100;
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

const state = struct {
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};
    var pass_action: sg.PassAction = .{};
    var scene: render_setup.SceneConfig = undefined;
    var allocator: std.mem.Allocator = undefined;
};

var shader_params: shd.FsParams = undefined;

export fn _init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    // Setup memory allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    state.allocator = arena.allocator();

    // Create a full-screen quad mesh
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&[_]f32{
            // positions         colors
            -1.0, 1.0, 0.0, 1.0, 0.0, 0.0, 1.0, // top-left
            -1.0, -1.0, 0.0, 0.0, 1.0, 0.0, 1.0, // bottom-left
            1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 1.0, // top-right
            1.0, -1.0, 0.0, 1.0, 1.0, 0.0, 1.0, // bottom-right
        }),
    });

    // Create index buffer for the quad (2 triangles)
    state.bind.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sg.asRange(&[_]u16{ 0, 1, 2, 2, 1, 3 }),
    });

    // Create the rendering pipeline
    state.pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.renderShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.attrs[shd.ATTR_render_position].format = .FLOAT3;
            l.attrs[shd.ATTR_render_color0].format = .FLOAT4;
            break :init l;
        },
        .index_type = .UINT16,
    });

    // Configure the clear color
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
    };

    // Create and configure the scene
    setupScene() catch |err| {
        std.debug.print("Error setting up scene: {}\n", .{err});
        return;
    };

    shader_params = render_setup.setupShaderParams(state.scene);
    std.debug.print("Initialization complete. Backend: {}\n", .{sg.queryBackend()});
}

fn setupScene() !void {
    // Create a world with spheres
    var world = HittableList.init(state.allocator);
    defer world.deinit();

    // Add a ground sphere
    const material_ground = Material.lambertian(@Vector(3, f32){ 0.5, 0.5, 0.5 });
    _ = try world.add(Sphere.init(init(0.0, -1000, 0), 1000, material_ground));

    // Add three main spheres
    const material1 = Material.dielectric(1.5);
    const material2 = Material.lambertian(init(0.4, 0.2, 0.1));
    const material3 = Material.metal(init(0.7, 0.6, 0.5), 0.0);

    _ = try world.add(Sphere.init(init(0, 1, 0), 1.0, material1));
    _ = try world.add(Sphere.init(init(-4, 1, 0), 1.0, material2));
    _ = try world.add(Sphere.init(init(4, 1, 0), 1.0, material3));

    // Add some random smaller spheres
    var a: f32 = -11;
    while (a < 11) : (a += 1) { // Changed from 0 to 11 to match CPU version
        var b: f32 = -11;
        while (b < 11) : (b += 1) { // Changed from 0 to 11 to match CPU version
            const choose_mat = rtw.random_double();
            const center: @Vector(3, f32) = @Vector(3, f32){ a + 0.9 * rtw.random_double(), 0.2, b + 0.9 * rtw.random_double() };

            if (try rtw.vec.magnitude(center - init(4.0, 0.2, 0.0)) > 0.9) {
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

    try world.buildBVH();

    // Create the scene configuration with camera setup
    state.scene = try render_setup.createSceneFromHittableList(
        state.allocator,
        &world,
        .{
            .samples_per_pixel = 100, // Start with a low sample count for interactive preview
            .max_depth = 20,
            .aspect_ratio = sapp.widthf() / sapp.heightf(),
            .vfov = 20.0, // Wider field of view
            .defocus_angle = 0.6, // No depth of field blur
            .focus_dist = 10.0,
            .lookfrom = init(13.0, 2.0, 3.0), // Adjusted camera position
            .lookat = init(0.0, 0.0, 0.0),
            .vup = init(0.0, 1.0, 0.0),
        },
    );
}

export fn frame() void {
    shader_params.u_resolution = .{ sapp.widthf(), sapp.heightf(), 0.0, 0.0 };

    // Render the scene
    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.applyUniforms(shd.UB_fs_params, sg.asRange(&shader_params));
    sg.draw(0, 6, 1);
    sg.endPass();
    sg.commit();

    std.debug.print("[INFO]     Avg Frame Duration: {d:.4}ms\n", .{sapp.frameDuration() * 1000.0});
}

export fn cleanup() void {

    //TODO:  state.allocator.free(state.scene.sphere) works in ReleaseFast, but segfaults in debug mode?

    //if (state.scene.spheres.len > 0) {
    //    state.allocator.free(state.scene.spheres);
    //}

    sg.shutdown();
}

pub fn main() !void {
    //try draw_ppm();
    sapp.run(.{
        .init_cb = _init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .width = 800,
        .height = 450,
        .sample_count = 1,
        .window_title = "Ray Tracer GPU",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
    });
}
