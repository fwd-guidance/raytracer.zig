const rtw = @import("rtweekend.zig");

const hittable_list = rtw.HittableList.HittableList;
const Ray = rtw.ray.Ray;
const hit_record = rtw.hittable.hit_record;
const std = rtw.std;
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
    aspect_ratio: f64,
    image_width: f64,
    image_height: f64,
    center: @Vector(3, f64),
    pixel00_loc: @Vector(3, f64),
    pixel_delta_u: @Vector(3, f64),
    pixel_delta_v: @Vector(3, f64),
    pixel_samples_scale: f64,
    vfov: f64,
    lookfrom: @Vector(3, f64),
    lookat: @Vector(3, f64),
    vup: @Vector(3, f64),
    u: @Vector(3, f64),
    v: @Vector(3, f64),
    w: @Vector(3, f64),
    defocus_angle: f64,
    focus_dist: f64,
    defocus_disk_u: @Vector(3, f64),
    defocus_disk_v: @Vector(3, f64),
    const Self = @This();

    pub fn render(self: *Self, world: *const hittable_list) !void {
        initialize(self);

        try stdout.print("P3\n{d} {d} \n255\n", .{ self.*.image_width, self.*.image_height });

        var j: f64 = 0;

        while (j < self.*.image_height) : (j += 1) {
            var i: f64 = 0;
            std.debug.print("\rScanlines remaining: {d}\n", .{self.*.image_height - j});
            while (i < self.*.image_width) : (i += 1) {
                var pixel_color = init(0, 0, 0);
                var sample: f32 = 0;
                while (sample < self.*.samples_per_pixel) : (sample += 1) {
                    const r: Ray = get_ray(self, i, j);
                    pixel_color += try ray_color(r, self.*.max_depth, world);
                }
                try color.write_color(try vec.scale(pixel_color, self.*.pixel_samples_scale));
            }
        }

        std.debug.print("\rDone.              \n", .{});
    }

    fn initialize(self: *Self) void {
        self.*.image_height = if ((self.*.image_width / self.*.aspect_ratio) > 1) self.*.image_width / self.*.aspect_ratio else 1;
        self.*.pixel_samples_scale = @as(f64, 1.0) / self.*.samples_per_pixel;
        self.*.center = self.*.lookfrom;

        // Camera
        const theta = std.math.degreesToRadians(self.vfov);
        const h = std.math.tan(theta / 2);
        const viewport_height: f64 = 2 * h * self.*.focus_dist;
        const viewport_width: f64 = viewport_height * @as(f64, self.*.image_width / self.*.image_height);
        self.*.w = try rtw.vec.unit(self.lookfrom - self.lookat);
        self.*.u = try rtw.vec.unit(try rtw.vec.cross(self.vup, self.w));
        self.*.v = try rtw.vec.cross(self.w, self.u);

        // Calculate the vectors across the horizontal and down the vertical viewport edges
        const viewport_u: @Vector(3, f64) = try vec.scale(self.*.u, viewport_width);
        const viewport_v: @Vector(3, f64) = try vec.scale(try vec.invert(self.*.v), viewport_height);

        // Calculate the hoirzontal and vertical delta vectors pixel to pixel
        self.*.pixel_delta_u = viewport_u / init(self.*.image_width, self.*.image_width, self.*.image_width);
        self.*.pixel_delta_v = viewport_v / init(self.*.image_height, self.*.image_height, self.*.image_height);

        // Calculate the location of the upper left pixel
        const viewport_upper_left: @Vector(3, f64) = self.center - (try vec.scale(self.*.w, self.*.focus_dist)) - (try vec.scale(viewport_u, 0.5)) - (try vec.scale(viewport_v, 0.5));
        self.*.pixel00_loc = viewport_upper_left + init(0.5, 0.5, 0.5) * (self.*.pixel_delta_u + self.*.pixel_delta_v);
        const defocus_radius: f64 = self.*.focus_dist * std.math.tan(std.math.degreesToRadians(self.*.defocus_angle / 2.0));
        self.*.defocus_disk_u = try vec.scale(self.*.u, defocus_radius);
        self.*.defocus_disk_v = try vec.scale(self.*.v, defocus_radius);
    }

    fn get_ray(self: *Self, i: f64, j: f64) Ray {
        // Construct a camera ray originating from the origin and directed at rnadomly sampled
        // point around the pixel location i, j
        const offset: @Vector(3, f64) = sample_square();
        const pixel_sample: @Vector(3, f64) = self.*.pixel00_loc + (init(i + offset[0], i + offset[0], i + offset[0]) * self.*.pixel_delta_u) + (init(j + offset[1], j + offset[1], j + offset[1]) * self.*.pixel_delta_v);
        const ray_origin: @Vector(3, f64) = if (self.*.defocus_angle <= 0) self.*.center else defocus_disk_sample(self);
        const ray_direction: @Vector(3, f64) = pixel_sample - ray_origin;
        const ray_time: f64 = random_double();

        return Ray{ .origin = ray_origin, .direction = ray_direction, .tm = ray_time };
    }

    fn sample_square() @Vector(3, f64) {
        return vec.init(random_double() - 0.5, random_double() - 0.5, 0);
    }

    fn defocus_disk_sample(self: *Self) @Vector(3, f64) {
        const p = try vec.random_in_unit_disk();
        return self.*.center + (try vec.scale(self.*.defocus_disk_u, p[0])) + (try vec.scale(self.*.defocus_disk_v, p[1]));
    }

    fn ray_color(r: Ray, depth: f64, world: *const hittable_list) !@Vector(3, f64) {
        if (depth <= 0) return init(0, 0, 0);

        var rec: hit_record = undefined;
        if (world.hit(r, Interval{ .min = 0.001, .max = std.math.inf(f64) }, @constCast(&rec))) {
            var scattered: Ray = undefined;
            var attenuation: @Vector(3, f64) = undefined;
            const is_scattered: bool = switch (rec.mat) {
                .Lambertian => |l| try l.scatter(&r, &rec, @constCast(&attenuation), @constCast(&scattered)),
                .Metal => |m| try m.scatter(&r, &rec, @constCast(&attenuation), @constCast(&scattered)),
                .Dielectric => |d| try d.scatter(&r, &rec, @constCast(&attenuation), @constCast(&scattered)),
            };
            if (is_scattered) {
                return attenuation * try ray_color(scattered, depth - 1, world);
            }
            return @Vector(3, f64){ 0.0, 0.0, 0.0 };
        }

        const unit_direction: @Vector(3, f64) = try vec.unit(r.direction);
        const a: f64 = 0.5 * (unit_direction[1] + 1.0);
        return try vec.scale(init(1.0, 1.0, 1.0), 1.0 - a) + try vec.scale(init(0.5, 0.7, 1.0), a);
    }
};
