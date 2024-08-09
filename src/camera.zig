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

pub const Camera = struct {
    samples_per_pixel: f32,
    aspect_ratio: f64,
    image_width: f64,
    image_height: f64,
    center: @Vector(3, f64),
    pixel00_loc: @Vector(3, f64),
    pixel_delta_u: @Vector(3, f64),
    pixel_delta_v: @Vector(3, f64),
    pixel_samples_scale: f64,
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
                    pixel_color += try ray_color(r, world);
                }
                try color.write_color(try vec.scale(pixel_color, self.*.pixel_samples_scale));
            }
        }

        std.debug.print("\rDone.              \n", .{});
    }

    fn initialize(self: *Self) void {
        self.*.image_height = if ((self.*.image_width / self.*.aspect_ratio) > 1) self.*.image_width / self.*.aspect_ratio else 1;
        self.*.pixel_samples_scale = @as(f64, 1.0) / self.*.samples_per_pixel;

        // Camera
        const focal_length: f64 = 1.0;
        const viewport_height: f64 = 2.0;
        const viewport_width: f64 = viewport_height * @as(f64, self.*.image_width / self.*.image_height);
        const camera_center: @Vector(3, f64) = self.*.center;

        // Calculate the vectors across the horizontal and down the vertical viewport edges
        const viewport_u: @Vector(3, f64) = init(viewport_width, 0, 0);
        const viewport_v: @Vector(3, f64) = init(0, -viewport_height, 0);

        // Calculate the hoirzontal and vertical delta vectors pixel to pixel
        self.*.pixel_delta_u = viewport_u / init(self.*.image_width, self.*.image_width, self.*.image_width);
        self.*.pixel_delta_v = viewport_v / init(self.*.image_height, self.*.image_height, self.*.image_height);

        // Calculate the location of the upper left pixel
        const viewport_upper_left: @Vector(3, f64) = camera_center - init(0, 0, focal_length) - (viewport_u * init(0.5, 0.5, 0.5)) - (viewport_v * init(0.5, 0.5, 0.5));
        self.*.pixel00_loc = viewport_upper_left + init(0.5, 0.5, 0.5) * (self.*.pixel_delta_u + self.*.pixel_delta_v);
    }

    fn get_ray(self: *Self, i: f64, j: f64) Ray {
        // Construct a camera ray originating from the origin and directed at rnadomly sampled
        // point around the pixel location i, j
        const offset: @Vector(3, f64) = sample_square();
        const pixel_sample: @Vector(3, f64) = self.*.pixel00_loc + (init(i + offset[0], i + offset[0], i + offset[0]) * self.*.pixel_delta_u) + (init(j + offset[1], j + offset[1], j + offset[1]) * self.*.pixel_delta_v);
        const ray_origin: @Vector(3, f64) = self.*.center;
        const ray_direction: @Vector(3, f64) = pixel_sample - ray_origin;

        return Ray{ .origin = ray_origin, .direction = ray_direction };
    }

    fn sample_square() @Vector(3, f64) {
        return vec.init(random_double() - 0.5, random_double() - 0.5, 0);
    }

    fn ray_color(r: Ray, world: *const hittable_list) !@Vector(3, f64) {
        const rec: hit_record = undefined;
        const result = (world.hit(r, Interval{ .min = 0, .max = std.math.inf(f64) }, @constCast(&rec)));
        if (result.ok) {
            return try vec.scale(result.result + init(1.0, 1.0, 1.0), 0.5);
        }

        const unit_direction: @Vector(3, f64) = try vec.unit(r.direction);
        const a: f64 = 0.5 * (unit_direction[1] + 1.0);
        return try vec.scale(init(1.0, 1.0, 1.0), 1.0 - a) + try vec.scale(init(0.5, 0.7, 1.0), a);
    }
};
