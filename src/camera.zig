const rtw = @import("rtweekend.zig");

const hittable_list = rtw.HittableList.HittableList;
const Ray = rtw.ray.Ray;
const hit_record = rtw.hittable.hit_record;
const std = rtw.std;
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const AtomicValue = std.atomic.Value;

const vec = rtw.vec;
const init = rtw.vec.init;
const color = rtw.color;
const Interval = rtw.interval.Interval;
const random_double = rtw.random_double;
const material = rtw.material;
const Result = material.Result;

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

        self.w = vec.unit(self.lookfrom - self.lookat);
        self.u = vec.unit(vec.cross(self.vup, self.w));
        self.v = vec.cross(self.w, self.u);

        const viewport_u: @Vector(3, f32) = vec.scale(self.u, viewport_width);
        const viewport_v: @Vector(3, f32) = vec.scale(vec.invert(self.v), viewport_height);

        self.pixel_delta_u = viewport_u * @as(@Vector(3, f32), @splat(1.0 / w_f));
        self.pixel_delta_v = viewport_v * @as(@Vector(3, f32), @splat(1.0 / h_f));

        const viewport_upper_left: @Vector(3, f32) = self.center -
            vec.scale(self.w, self.focus_dist) -
            vec.scale(viewport_u, 0.5) -
            vec.scale(viewport_v, 0.5);
        self.pixel00_loc = viewport_upper_left + init(0.5, 0.5, 0.5) * (self.pixel_delta_u + self.pixel_delta_v);

        const defocus_radius: f32 = self.focus_dist * std.math.tan(std.math.degreesToRadians(self.defocus_angle / 2.0));
        self.defocus_disk_u = vec.scale(self.u, defocus_radius);
        self.defocus_disk_v = vec.scale(self.v, defocus_radius);
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
            pixel.* = init(0, 0, 0);
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
                        var pixel_color = init(0, 0, 0);

                        var sample: u32 = 0;
                        while (sample < camera.samples_per_pixel) : (sample += 1) {
                            const r: Ray = get_ray(camera, i, j);
                            pixel_color += ray_color(r, camera.max_depth, world_objects);
                        }

                        const buffer_index = @as(usize, j) * @as(usize, cam_width) + @as(usize, i);
                        context.buffer.items[buffer_index] = vec.scale(pixel_color, camera.pixel_samples_scale);
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
            try color.write_color(&writer.interface, pixel);
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
        return vec.init(random_double() - 0.5, random_double() - 0.5, 0);
    }

    fn defocus_disk_sample(self: *Self) @Vector(3, f32) {
        const p = vec.random_in_unit_disk();
        return self.center + vec.scale(self.defocus_disk_u, p[0]) + vec.scale(self.defocus_disk_v, p[1]);
    }

    /// Recursive ray colour.  Now fully error-free — all vec and material
    /// scatter calls are infallible.  Depth is an integer counter.
    fn ray_color(r: Ray, depth: u32, world: *const hittable_list) @Vector(3, f32) {
        if (depth <= 0) return init(0, 0, 0);

        var rec: hit_record = undefined;
        const hit_result = world.hit(r, Interval{ .min = 0.001, .max = std.math.inf(f32) }, &rec);

        if (try hit_result) {
            var scattered: Ray = undefined;
            var attenuation: @Vector(3, f32) = undefined;

            const mat = world.materials.items[rec.mat_id];

            switch (mat) {
                .Lambertian => |l| {
                    if (l.scatter(&r, &rec, &attenuation, &scattered)) {
                        attenuation = world.textures.items[l.tex_id].value(rec.u, rec.v, rec.p);
                        return attenuation * ray_color(scattered, depth - 1, world);
                    }
                },
                .Metal => |m| {
                    if (m.scatter(&r, &rec, &attenuation, &scattered)) {
                        return attenuation * ray_color(scattered, depth - 1, world);
                    }
                },
                .Dielectric => |d| {
                    if (d.scatter(&r, &rec, &attenuation, &scattered)) {
                        return attenuation * ray_color(scattered, depth - 1, world);
                    }
                },
            }

            return @Vector(3, f32){ 0.0, 0.0, 0.0 };
        }

        // Sky gradient
        const unit_direction: @Vector(3, f32) = vec.unit(r.direction);
        const a: f32 = 0.5 * (unit_direction[1] + 1.0);
        return vec.scale(init(1.0, 1.0, 1.0), 1.0 - a) + vec.scale(init(0.5, 0.7, 1.0), a);
    }
};
