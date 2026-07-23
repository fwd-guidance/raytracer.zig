const math = @import("math.zig");
const scene = @import("scene.zig");
const utils = @import("utils.zig");
const pdf = @import("pdf.zig");

const hittable_list = scene.HittableList;
const Ray = math.Ray;
const HitRecord = scene.HitRecord;
const std = @import("std");
const Thread = std.Thread;
const Mutex = std.Io.Mutex;
const AtomicValue = std.atomic.Value;

const Interval = math.Interval;
const random_double = utils.random_double;
const material = @import("material.zig").Material;
const ScatterRecord = @import("material.zig").ScatterRecord;

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
    sqrt_samples_per_pixel: u32,
    recip_sqrt_samples_per_pixel: f32,
    const Self = @This();

    pub fn initialize(self: *Self) void {
        const w_f = math.tof32(self.image_width);
        const h_f = math.tof32(@max(1, math.tou32(w_f / self.aspect_ratio)));
        self.image_height = math.tou32(h_f);

        self.sqrt_samples_per_pixel = math.tou32(@sqrt(math.tof32(self.samples_per_pixel)));
        self.pixel_samples_scale = 1.0 / math.tof32(self.sqrt_samples_per_pixel * self.sqrt_samples_per_pixel);
        self.recip_sqrt_samples_per_pixel = 1.0 / math.tof32(self.sqrt_samples_per_pixel);

        self.center = self.lookfrom;

        const theta = std.math.degreesToRadians(self.vfov);
        const h = std.math.tan(theta / 2);
        const viewport_height: f32 = 2 * h * self.focus_dist;
        const viewport_width: f32 = viewport_height * (w_f / h_f);

        self.w = math.unit(self.lookfrom - self.lookat);
        self.u = math.unit(math.cross(self.vup, self.w));
        self.v = math.cross(self.w, self.u);

        const viewport_u: @Vector(3, f32) = math.scale(self.u, viewport_width);
        const viewport_v: @Vector(3, f32) = math.scale(-self.v, viewport_height);

        self.pixel_delta_u = viewport_u * math.vec3s(1.0 / w_f);
        self.pixel_delta_v = viewport_v * math.vec3s(1.0 / h_f);

        const viewport_upper_left: @Vector(3, f32) = self.center -
            math.scale(self.w, self.focus_dist) -
            math.scale(viewport_u, 0.5) -
            math.scale(viewport_v, 0.5);
        self.pixel00_loc = viewport_upper_left + math.init(0.5, 0.5, 0.5) * (self.pixel_delta_u + self.pixel_delta_v);

        const defocus_radius: f32 = self.focus_dist * std.math.tan(std.math.degreesToRadians(self.defocus_angle / 2.0));
        self.defocus_disk_u = math.scale(self.u, defocus_radius);
        self.defocus_disk_v = math.scale(self.v, defocus_radius);
    }

    pub fn render(self: *Self, world: *const hittable_list, lights: *const hittable_list) !void {
        self.initialize();
        self.mutex = .init;

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
            lights: *const hittable_list,
            start_row: u32,
            end_row: u32,
            rows_completed: *AtomicValue(u32),
            buffer: *std.ArrayList(@Vector(3, f32)),
        };

        const renderToBuffer = struct {
            fn worker(context: *BufferedRenderContext) void {
                const camera = context.camera;
                const world_objects = context.world;
                const light_objects = context.lights;
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

                        var s_j: u32 = 0;
                        while (s_j < camera.sqrt_samples_per_pixel) : (s_j += 1) {
                            var s_i: u32 = 0;
                            while (s_i < camera.sqrt_samples_per_pixel) : (s_i += 1) {
                                const r: Ray = get_ray(camera, i, j, s_i, s_j);
                                pixel_color += ray_color(camera, r, camera.max_depth, world_objects, light_objects);
                            }
                        }

                        //var sample: u32 = 0;
                        //while (sample < camera.samples_per_pixel) : (sample += 1) {
                        //    const r: Ray = get_ray(camera, i, j);
                        //    pixel_color += ray_color(camera, r, camera.max_depth, world_objects);
                        //}

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
                .lights = lights,
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

        const stdout_file = std.Io.File.stdout();
        var buffer: [65536]u8 = undefined; // larger output buffer reduces syscall count
        var threaded: std.Io.Threaded = .init_single_threaded;
        const io = threaded.io();
        var writer = stdout_file.writer(io, &buffer);

        try writer.interface.print("P3\n{d} {d} \n255\n", .{ width, height });

        for (pixel_buffer.items) |pixel| {
            try write_color(&writer.interface, pixel);
        }

        try writer.interface.flush();
        std.debug.print("\n", .{});
    }

    /// Construct a camera ray for pixel (i, j) with a random sub-pixel offset.
    /// Uses integer pixel coords and splat for broadcasting.
    fn get_ray(self: *Self, i: u32, j: u32, s_i: u32, s_j: u32) Ray {
        const offset: @Vector(3, f32) = sample_square_stratified(self, s_i, s_j);
        const fi = math.tof32(i);
        const fj = math.tof32(j);
        const pixel_sample: @Vector(3, f32) =
            self.pixel00_loc +
            math.vec3s(fi + offset[0]) * self.pixel_delta_u +
            math.vec3s(fj + offset[1]) * self.pixel_delta_v;
        const ray_origin: @Vector(3, f32) = if (self.defocus_angle <= 0) self.center else defocus_disk_sample(self);
        const ray_direction: @Vector(3, f32) = pixel_sample - ray_origin;
        const ray_time: f32 = random_double();

        return Ray.init(ray_origin, ray_direction, ray_time);
    }

    fn sample_square_stratified(self: *Self, s_i: u32, s_j: u32) @Vector(3, f32) {
        const px = ((math.tof32(s_i) + random_double()) * self.recip_sqrt_samples_per_pixel) - 0.5;
        const py = ((math.tof32(s_j) + random_double()) * self.recip_sqrt_samples_per_pixel) - 0.5;
        return @Vector(3, f32){ px, py, 0 };
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
    fn ray_color(camera: *const Self, r: Ray, depth: u32, world: *const hittable_list, lights: *const hittable_list) @Vector(3, f32) {
        // If we've exceeded the ray bounce limit, no more light is gathered
        if (depth <= 0) return math.init(0, 0, 0);

        var rec: HitRecord = undefined;
        if (!world.hit(r, Interval{ .min = 0.001, .max = std.math.inf(f32) }, &rec)) {
            return camera.background;
        }

        var srec: ScatterRecord = undefined;
        const mat = world.materials.items[rec.mat_id];

        // Get emitted color from the material (black for non-emissive materials)
        const color_from_emission = mat.emitted(&r, &rec, rec.u, rec.v, rec.p, world.textures.items);

        // Try to scatter the ray
        // Use the unified Material.scatter() method or handle each case
        const did_scatter = mat.scatter(&r, &rec, &srec, world.textures.items);

        // If the material doesn't scatter, return only the emitted color
        if (!did_scatter) {
            return color_from_emission;
        }

        if (srec.skip_pdf) {
            return srec.attenuation * ray_color(camera, srec.skip_pdf_ray, depth - 1, world, lights);
        }

        const light_pdf = pdf.PDF{ .hittable = pdf.HittablePDF.init(lights, rec.p) };
        const p = pdf.MixturePDF.init(&light_pdf, &srec.pdf_value.?);

        var scattered = Ray.init(rec.p, p.generate(), r.tm);
        const pdf_value = p.value(scattered.direction);

        const scattering_pdf = world.materials.items[rec.mat_id].scattering_pdf(&r, &rec, &scattered);

        const color_from_scatter = (srec.attenuation * math.vec3s(scattering_pdf) * ray_color(camera, scattered, depth - 1, world, lights)) / math.vec3s(pdf_value);

        // Return combined emission and scatter
        return color_from_emission + color_from_scatter;
    }
};

pub fn linear_to_gamma(linear_component: f32) f32 {
    if (linear_component > 0) return @sqrt(linear_component) else return 0;
}

inline fn write_u8(writer: anytype, value: u8) !void {
    if (value >= 100) {
        try writer.writeByte('0' + value / 100);
    }
    if (value >= 10) {
        try writer.writeByte('0' + (value / 10) % 10);
    }
    try writer.writeByte('0' + value % 10);
}

pub fn write_color(writer: anytype, pixel_color: @Vector(3, f32)) !void {
    var r = pixel_color[0];
    var g = pixel_color[1];
    var b = pixel_color[2];

    if (r != r) r = 0.0;
    if (g != g) g = 0.0;
    if (b != b) b = 0.0;

    r = linear_to_gamma(r);
    g = linear_to_gamma(g);
    b = linear_to_gamma(b);

    const intensity: Interval = Interval{ .min = 0.000, .max = 0.999 };
    const rbyte = @as(u8, @intFromFloat(256 * intensity.clamp(r)));
    const gbyte = @as(u8, @intFromFloat(256 * intensity.clamp(g)));
    const bbyte = @as(u8, @intFromFloat(256 * intensity.clamp(b)));

    try write_u8(writer, rbyte);
    try writer.writeByte(' ');
    try write_u8(writer, gbyte);
    try writer.writeByte(' ');
    try write_u8(writer, bbyte);
    try writer.writeByte('\n');
}
