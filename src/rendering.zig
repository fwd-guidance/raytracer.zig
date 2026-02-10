const math = @import("math.zig");
const scene = @import("scene.zig");
const utils = @import("utils.zig");

const hittable_list = scene.HittableList;
const Ray = math.Ray;
const hit_record = scene.hit_record;
const std = @import("std");
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const AtomicValue = std.atomic.Value;

const Interval = math.Interval;
const random_double = utils.random_double;
const material = @import("material.zig").Material;

pub const Camera = struct {
    samples_per_pixel: u32, //f32,
    max_depth: u32, //f32,
    aspect_ratio: f32,
    image_width: u32, //f32,
    image_height: u32, //f32,
    center: @Vector(3, f32),
    pixel00_loc: @Vector(3, f32),
    pixel_delta_u: @Vector(3, f32),
    pixel_delta_v: @Vector(3, f32),
    pixel_samples_scale: f32,
    vfov: f32,
    lookfrom: @Vector(3, f32),
    lookat: @Vector(3, f32),
    vup: @Vector(3, f32),
    u: @Vector(3, f32),
    v: @Vector(3, f32),
    w: @Vector(3, f32),
    defocus_angle: f32,
    focus_dist: f32,
    defocus_disk_u: @Vector(3, f32),
    defocus_disk_v: @Vector(3, f32),
    mutex: Mutex,
    num_threads: usize,
    background: @Vector(3, f32),
    const Self = @This();

    pub fn initialize(self: *Self) void {
        const w_f = @as(f32, @floatFromInt(self.image_width));
        const h_f = @as(f32, @floatFromInt(@max(1, @as(u32, @intFromFloat(w_f / self.aspect_ratio)))));
        self.image_height = @as(u32, @intFromFloat(h_f));

        self.pixel_samples_scale = 1.0 / @as(f32, @floatFromInt(self.samples_per_pixel));
        self.center = self.lookfrom;

        const theta = std.math.degreesToRadians(self.vfov);
        const h = std.math.tan(theta / 2);
        const viewport_height: f32 = 2 * h * self.focus_dist;
        const viewport_width: f32 = viewport_height * (w_f / h_f);

        self.w = math.unit(self.lookfrom - self.lookat);
        self.u = math.unit(math.cross(self.vup, self.w));
        self.v = math.cross(self.w, self.u);

        const viewport_u: @Vector(3, f32) = math.scale(self.u, viewport_width);
        const viewport_v: @Vector(3, f32) = math.scale(math.invert(self.v), viewport_height);

        self.pixel_delta_u = viewport_u * @as(@Vector(3, f32), @splat(1.0 / w_f));
        self.pixel_delta_v = viewport_v * @as(@Vector(3, f32), @splat(1.0 / h_f));

        const viewport_upper_left: @Vector(3, f32) = self.center -
            math.scale(self.w, self.focus_dist) -
            math.scale(viewport_u, 0.5) -
            math.scale(viewport_v, 0.5);
        self.pixel00_loc = viewport_upper_left + math.init(0.5, 0.5, 0.5) * (self.pixel_delta_u + self.pixel_delta_v);

        const defocus_radius: f32 = self.focus_dist * std.math.tan(std.math.degreesToRadians(self.defocus_angle / 2.0));
        self.defocus_disk_u = math.scale(self.u, defocus_radius);
        self.defocus_disk_v = math.scale(self.v, defocus_radius);
    }

    pub fn render(self: *Self, world: *const hittable_list) !void {
        self.initialize();
        self.mutex = Mutex{};

        // Use all available cores instead of a hard-coded 4.
        self.num_threads = Thread.getCpuCount() catch 4;

        const width = self.image_width;
        const height = self.image_height;
        const total_pixels = @as(usize, width) * @as(usize, height);

        var pixel_buffer = try std.ArrayList(@Vector(3, f32)).initCapacity(std.heap.page_allocator, total_pixels);
        defer pixel_buffer.deinit(std.heap.page_allocator);

        try pixel_buffer.resize(std.heap.page_allocator, total_pixels);
        for (pixel_buffer.items) |*pixel| {
            pixel.* = math.init(0, 0, 0);
        }

        std.debug.print("Rendering with {d} threads\n", .{self.num_threads});

        var rows_completed = AtomicValue(u32).init(0);

        const BufferedRenderContext = struct {
            camera: *Camera,
            world: *const hittable_list,
            start_row: u32,
            end_row: u32,
            rows_completed: *AtomicValue(u32),
            buffer: *std.ArrayList(@Vector(3, f32)),
        };

        const renderToBuffer = struct {
            fn worker(context: *BufferedRenderContext) void {
                const camera = context.camera;
                const world_objects = context.world;
                const cam_width = camera.image_width;

                var j: u32 = context.start_row;
                while (j < context.end_row) : (j += 1) {
                    // Progress reporting every 10 rows
                    if (j % 10 == 0) {
                        _ = context.rows_completed.fetchAdd(10, .monotonic);
                        const rows_done = context.rows_completed.load(.monotonic);
                        const rows_total = camera.image_height;
                        if (rows_done <= rows_total) {
                            std.debug.print("\rScanlines remaining: {d}    ", .{rows_total - rows_done});
                        }
                    }

                    var i: u32 = 0;
                    while (i < cam_width) : (i += 1) {
                        var pixel_color = math.init(0, 0, 0);

                        var sample: u32 = 0;
                        while (sample < camera.samples_per_pixel) : (sample += 1) {
                            const r: Ray = get_ray(camera, i, j);
                            pixel_color += ray_color(camera, r, camera.max_depth, world_objects);
                        }

                        const buffer_index = @as(usize, j) * @as(usize, cam_width) + @as(usize, i);
                        context.buffer.items[buffer_index] = math.scale(pixel_color, camera.pixel_samples_scale);
                    }
                }
            }
        }.worker;

        // Calculate rows per thread using integer ceiling division
        const rows_per_thread = (self.image_height + self.num_threads - 1) / self.num_threads;

        var threads = try std.ArrayList(Thread).initCapacity(std.heap.page_allocator, self.num_threads);
        defer threads.deinit(std.heap.page_allocator);

        var contexts = try std.ArrayList(BufferedRenderContext).initCapacity(std.heap.page_allocator, self.num_threads);
        defer contexts.deinit(std.heap.page_allocator);

        for (0..self.num_threads) |t| {
            const start_row = @as(u32, @intCast(t * rows_per_thread));
            const end_row = @min(start_row + rows_per_thread, self.image_height);

            if (start_row >= end_row) continue;

            try contexts.append(std.heap.page_allocator, BufferedRenderContext{
                .camera = self,
                .world = world,
                .start_row = start_row,
                .end_row = end_row,
                .rows_completed = &rows_completed,
                .buffer = &pixel_buffer,
            });

            try threads.append(std.heap.page_allocator, try Thread.spawn(.{}, renderToBuffer, .{&contexts.items[contexts.items.len - 1]}));
        }

        for (threads.items) |thread| {
            thread.join();
        }

        // Write output

        const stdout_file = std.fs.File.stdout();
        var buffer: [65536]u8 = undefined; // larger output buffer reduces syscall count
        var writer = stdout_file.writer(&buffer);

        try writer.interface.print("P3\n{d} {d} \n255\n", .{ width, height });

        for (pixel_buffer.items) |pixel| {
            try write_color(&writer.interface, pixel);
        }

        try writer.interface.flush();
        std.debug.print("\n", .{});
    }

    /// Construct a camera ray for pixel (i, j) with a random sub-pixel offset.
    /// Uses integer pixel coords and splat for broadcasting.
    fn get_ray(self: *Self, i: u32, j: u32) Ray {
        const offset: @Vector(3, f32) = sample_square();
        const fi = @as(f32, @floatFromInt(i));
        const fj = @as(f32, @floatFromInt(j));
        const pixel_sample: @Vector(3, f32) =
            self.pixel00_loc +
            @as(@Vector(3, f32), @splat(fi + offset[0])) * self.pixel_delta_u +
            @as(@Vector(3, f32), @splat(fj + offset[1])) * self.pixel_delta_v;
        const ray_origin: @Vector(3, f32) = if (self.defocus_angle <= 0) self.center else defocus_disk_sample(self);
        const ray_direction: @Vector(3, f32) = pixel_sample - ray_origin;
        const ray_time: f32 = random_double();

        return Ray.init(ray_origin, ray_direction, ray_time);
    }

    fn sample_square() @Vector(3, f32) {
        return math.init(random_double() - 0.5, random_double() - 0.5, 0);
    }

    fn defocus_disk_sample(self: *Self) @Vector(3, f32) {
        const p = math.random_in_unit_disk();
        return self.center + math.scale(self.defocus_disk_u, p[0]) + math.scale(self.defocus_disk_v, p[1]);
    }

    /// Recursive ray colour with emissive material support.
    /// Returns the color contribution from both emitted light and scattered rays.
    fn ray_color(camera: *const Self, r: Ray, depth: u32, world: *const hittable_list) @Vector(3, f32) {
        // If we've exceeded the ray bounce limit, no more light is gathered
        if (depth <= 0) return math.init(0, 0, 0);

        var rec: hit_record = undefined;
        const hit_result = world.hit(r, Interval{ .min = 0.001, .max = std.math.inf(f32) }, &rec);

        // If the ray hits nothing, return the background color
        if (!(try hit_result)) {
            return camera.background;
        }

        var scattered: Ray = undefined;
        var attenuation: @Vector(3, f32) = undefined;

        const mat = world.materials.items[rec.mat_id];

        // Get emitted color from the material (black for non-emissive materials)
        const color_from_emission = mat.emitted(rec.u, rec.v, rec.p, world.textures.items);

        // Try to scatter the ray
        // Use the unified Material.scatter() method or handle each case
        const did_scatter = switch (mat) {
            .Lambertian => |l| blk: {
                if (l.scatter(&r, &rec, &attenuation, &scattered)) {
                    // Override attenuation with texture value for Lambertian
                    attenuation = world.textures.items[l.tex_id].value(rec.u, rec.v, rec.p);
                    break :blk true;
                }
                break :blk false;
            },
            .Isotropic => |i| blk: {
                scattered = Ray.init(rec.p, math.random_unit_vector(), r.tm);
                attenuation = world.textures.items[i.tex_id].value(rec.u, rec.v, rec.p);
                break :blk true;
            },
            .Metal => |m| m.scatter(&r, &rec, &attenuation, &scattered),
            .Dielectric => |d| d.scatter(&r, &rec, &attenuation, &scattered),
            .DiffuseLight => false, // Lights don't scatter
        };

        // If the material doesn't scatter, return only the emitted color
        if (!did_scatter) {
            return color_from_emission;
        }

        // Calculate color from scattered ray
        const color_from_scatter = attenuation * ray_color(camera, scattered, depth - 1, world);

        // Return combined emission and scatter
        return color_from_emission + color_from_scatter;
    }
};

pub fn linear_to_gamma(linear_component: f32) f32 {
    if (linear_component > 0) return @sqrt(linear_component) else return 0;
}

inline fn writeU8(writer: anytype, value: u8) !void {
    if (value >= 100) {
        try writer.writeByte('0' + value / 100);
    }
    if (value >= 10) {
        try writer.writeByte('0' + (value / 10) % 10);
    }
    try writer.writeByte('0' + value % 10);
}

pub fn write_color(writer: anytype, pixel_color: @Vector(3, f32)) !void {
    const r: f32 = linear_to_gamma(pixel_color[0]);
    const g: f32 = linear_to_gamma(pixel_color[1]);
    const b: f32 = linear_to_gamma(pixel_color[2]);

    const intensity: Interval = Interval{ .min = 0.000, .max = 0.999 };
    const rbyte = @as(u8, @intFromFloat(256 * intensity.clamp(r)));
    const gbyte = @as(u8, @intFromFloat(256 * intensity.clamp(g)));
    const bbyte = @as(u8, @intFromFloat(256 * intensity.clamp(b)));

    try writeU8(writer, rbyte);
    try writer.writeByte(' ');
    try writeU8(writer, gbyte);
    try writer.writeByte(' ');
    try writeU8(writer, bbyte);
    try writer.writeByte('\n');
}
