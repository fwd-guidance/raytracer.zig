const rtw = @import("rtweekend.zig");
//const tracy = @import("tracy.zig");

const hittable_list = rtw.HittableList.HittableList;
const Ray = rtw.ray.Ray;
const hit_record = rtw.hittable.hit_record;
const std = rtw.std;
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const AtomicValue = std.atomic.Value;
const stdout = rtw.std.io.getStdOut().writer();
const vec = rtw.vec;
const init = rtw.vec.init;
const color = rtw.color;
const Interval = rtw.interval.Interval;
const random_double = rtw.random_double;
const material = rtw.material;
const Result = material.Result;

pub const Camera = struct {
    samples_per_pixel: f32,
    max_depth: f32,
    aspect_ratio: f32,
    image_width: f32,
    image_height: f32,
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

    // This struct is only used for type compatibility with old code
    // and can be removed if there are no other references to it
    const RenderWorkerContext = struct {
        camera: *Camera,
        world: *const hittable_list,
        start_row: usize,
        end_row: usize,
        rows_completed: *AtomicValue(u32),
    };

    // Public method to initialize the camera (without rendering)
    pub fn initialize(self: *Self) void {
        self.image_height = if ((self.image_width / self.aspect_ratio) > 1) self.image_width / self.aspect_ratio else 1;
        self.pixel_samples_scale = @as(f32, 1.0) / self.samples_per_pixel;
        self.center = self.lookfrom;

        // Camera
        const theta = std.math.degreesToRadians(self.vfov);
        const h = std.math.tan(theta / 2);
        const viewport_height: f32 = 2 * h * self.focus_dist;
        const viewport_width: f32 = viewport_height * @as(f32, self.image_width / self.image_height);
        self.w = rtw.vec.unit(self.lookfrom - self.lookat) catch @Vector(3, f32){ 0, 0, 1 };
        self.u = rtw.vec.unit(rtw.vec.cross(self.vup, self.w) catch @Vector(3, f32){ 1, 0, 0 }) catch @Vector(3, f32){ 1, 0, 0 };
        self.v = rtw.vec.cross(self.w, self.u) catch @Vector(3, f32){ 0, 1, 0 };

        // Calculate the vectors across the horizontal and down the vertical viewport edges
        const viewport_u: @Vector(3, f32) = vec.scale(self.u, viewport_width) catch self.u;
        const viewport_v: @Vector(3, f32) = vec.scale(vec.invert(self.v) catch -self.v, viewport_height) catch -self.v;

        // Calculate the horizontal and vertical delta vectors pixel to pixel
        self.pixel_delta_u = viewport_u / init(self.image_width, self.image_width, self.image_width);
        self.pixel_delta_v = viewport_v / init(self.image_height, self.image_height, self.image_height);

        // Calculate the location of the upper left pixel
        const viewport_upper_left: @Vector(3, f32) = self.center - 
            (vec.scale(self.w, self.focus_dist) catch self.w) - 
            (vec.scale(viewport_u, 0.5) catch viewport_u) - 
            (vec.scale(viewport_v, 0.5) catch viewport_v);
        self.pixel00_loc = viewport_upper_left + init(0.5, 0.5, 0.5) * (self.pixel_delta_u + self.pixel_delta_v);
        const defocus_radius: f32 = self.focus_dist * std.math.tan(std.math.degreesToRadians(self.defocus_angle / 2.0));
        self.defocus_disk_u = vec.scale(self.u, defocus_radius) catch self.u;
        self.defocus_disk_v = vec.scale(self.v, defocus_radius) catch self.v;
    }

    pub fn render(self: *Self, world: *const hittable_list) !void {
        self.initialize();

        // Initialize mutex for thread synchronization
        self.mutex = Mutex{};

        // Set number of threads based on available CPU cores
        // We don't need to limit to 16 threads if the system has more cores
        //self.num_threads = Thread.getCpuCount() catch 4;
        self.num_threads = 4;

        // Create a buffer to store all pixels before writing to output
        const total_pixels = @as(usize, @intFromFloat(self.image_width * self.image_height));

        var pixel_buffer = try std.ArrayList(@Vector(3, f32)).initCapacity(std.heap.page_allocator, total_pixels);
        defer pixel_buffer.deinit();

        // Pre-allocate with black pixels
        try pixel_buffer.resize(total_pixels);
        for (pixel_buffer.items) |*pixel| {
            pixel.* = init(0, 0, 0);
        }

        std.debug.print("Rendering with {d} threads\n", .{self.num_threads});

        // Create an atomic counter for progress tracking
        var rows_completed = AtomicValue(u32).init(0);

        // New rendering context that includes the pixel buffer
        const BufferedRenderContext = struct {
            camera: *Camera,
            world: *const hittable_list,
            start_row: usize,
            end_row: usize,
            rows_completed: *AtomicValue(u32),
            buffer: *std.ArrayList(@Vector(3, f32)),
        };

        // New worker function that renders to the buffer
        const renderToBuffer = struct {
            fn worker(context: *BufferedRenderContext) !void {
                const camera = context.camera;
                const world_objects = context.world;
                const start_row = context.start_row;
                const end_row = context.end_row;
                const buffer = context.buffer;

                var j: f32 = @as(f32, @floatFromInt(start_row));
                while (j < @as(f32, @floatFromInt(end_row))) : (j += 1) {
                    var i: f32 = 0;

                    // Occasionally update progress
                    if (@mod(@as(u32, @intFromFloat(j)), 10) == 0) {
                        _ = context.rows_completed.fetchAdd(10, .monotonic);
                        const rows_done = context.rows_completed.load(.monotonic);
                        const rows_total = @as(u32, @intFromFloat(camera.image_height));
                        if (rows_done <= rows_total) {
                            std.debug.print("\rScanlines remaining: {d}    ", .{rows_total - rows_done});
                        }
                    }

                    while (i < camera.image_width) : (i += 1) {
                        var pixel_color = init(0, 0, 0);
                        var sample: f32 = 0;
                        while (sample < camera.samples_per_pixel) : (sample += 1) {
                            const r: Ray = get_ray(camera, i, j);

                            pixel_color += try ray_color(r, camera.max_depth, world_objects);
                        }

                        // Calculate buffer index based on image coordinates
                        const buffer_index = @as(usize, @intFromFloat(j * camera.image_width + i));
                        buffer.items[buffer_index] = try vec.scale(pixel_color, camera.pixel_samples_scale);
                    }
                }
            }
        }.worker;

        // Calculate rows per thread
        const rows_per_thread = @as(usize, @intFromFloat(@ceil(self.image_height / @as(f32, @floatFromInt(self.num_threads)))));

        // Create and start worker threads
        var threads = try std.ArrayList(Thread).initCapacity(std.heap.page_allocator, self.num_threads);
        defer threads.deinit();

        var contexts = try std.ArrayList(BufferedRenderContext).initCapacity(std.heap.page_allocator, self.num_threads);
        defer contexts.deinit();

        for (0..self.num_threads) |t| {
            const start_row = t * rows_per_thread;
            const end_row = @min(start_row + rows_per_thread, @as(usize, @intFromFloat(self.image_height)));

            // Skip empty ranges
            if (start_row >= end_row) continue;

            // Create context for this thread
            try contexts.append(BufferedRenderContext{
                .camera = self,
                .world = world,
                .start_row = start_row,
                .end_row = end_row,
                .rows_completed = &rows_completed,
                .buffer = &pixel_buffer,
            });

            // Spawn thread
            try threads.append(try Thread.spawn(.{}, renderToBuffer, .{&contexts.items[contexts.items.len - 1]}));
        }

        // Wait for all threads to complete
        for (threads.items) |thread| {
            thread.join();
        }

        // Now write the completed buffer to the output in the correct order
        try stdout.print("P3\n{d} {d} \n255\n", .{ self.image_width, self.image_height });

        for (pixel_buffer.items) |pixel| {
            try color.write_color(pixel);
        }

        std.debug.print("\rDone.                            \n", .{});
    }

    fn get_ray(self: *Self, i: f32, j: f32) Ray {
        // Construct a camera ray originating from the origin and directed at randomly sampled
        // point around the pixel location i, j
        const offset: @Vector(3, f32) = sample_square();
        const pixel_sample: @Vector(3, f32) = self.pixel00_loc + (init(i + offset[0], i + offset[0], i + offset[0]) * self.pixel_delta_u) + (init(j + offset[1], j + offset[1], j + offset[1]) * self.pixel_delta_v);
        const ray_origin: @Vector(3, f32) = if (self.defocus_angle <= 0) self.center else defocus_disk_sample(self);
        const ray_direction: @Vector(3, f32) = pixel_sample - ray_origin;
        const ray_time: f32 = random_double();

        return Ray{ .origin = ray_origin, .direction = ray_direction, .tm = ray_time };
    }

    fn sample_square() @Vector(3, f32) {
        return vec.init(random_double() - 0.5, random_double() - 0.5, 0);
    }

    fn defocus_disk_sample(self: *Self) @Vector(3, f32) {
        const p = try vec.random_in_unit_disk();
        return self.center + (try vec.scale(self.defocus_disk_u, p[0])) + (try vec.scale(self.defocus_disk_v, p[1]));
    }

    fn ray_color(r: Ray, depth: f32, world: *const hittable_list) !@Vector(3, f32) {
        if (depth <= 0) return init(0, 0, 0);

        var rec: hit_record = undefined;
        const hit_result = world.hit(r, Interval{ .min = 0.001, .max = std.math.inf(f32) }, @constCast(&rec));

        if (hit_result) {
            var scattered: Ray = undefined;
            var attenuation: @Vector(3, f32) = undefined;
            const is_scattered: bool = switch (rec.mat) {
                .Lambertian => |l| try l.scatter(&r, &rec, @constCast(&attenuation), @constCast(&scattered)),
                .Metal => |m| try m.scatter(&r, &rec, @constCast(&attenuation), @constCast(&scattered)),
                .Dielectric => |d| try d.scatter(&r, &rec, @constCast(&attenuation), @constCast(&scattered)),
            };

            if (is_scattered) {
                const result = attenuation * try ray_color(scattered, depth - 1, world);
                return result;
            }
            return @Vector(3, f32){ 0.0, 0.0, 0.0 };
        }

        const unit_direction: @Vector(3, f32) = try vec.unit(r.direction);
        const a: f32 = 0.5 * (unit_direction[1] + 1.0);
        const result = try vec.scale(init(1.0, 1.0, 1.0), 1.0 - a) + try vec.scale(init(0.5, 0.7, 1.0), a);
        return result;
    }
};
