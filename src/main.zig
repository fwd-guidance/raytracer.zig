const vec = @import("vec.zig");
const init = @import("vec.zig").init;
const color = @import("color.zig");
const ray = @import("ray.zig");

const std = @import("std");

pub fn hit_sphere(center: @Vector(3, f64), radius: f64, r: ray.Ray) !f64 {
    const oc: @Vector(3, f64) = center - r.origin;
    const a: f64 = try vec.square_magnitude(r.direction);
    const h: f64 = try vec.dot(r.direction, oc);
    const c: f64 = try vec.square_magnitude(oc) - radius * radius;
    const discriminant: f64 = h * h - a * c;
    if (discriminant < 0) {
        return -1.0;
    } else {
        return (h - @sqrt(discriminant)) / a;
    }
}

pub fn ray_color(r: ray.Ray) !@Vector(3, f64) {
    const t: f64 = try hit_sphere(init(0, 0, -1), 0.5, r);
    if (t > 0.0) {
        const N: @Vector(3, f64) = try vec.unit(try r.position(t) - init(0, 0, -1));
        return try vec.scale(init(N[0] + 1, N[1] + 1, N[2] + 1), 0.5);
    }

    const unit_direction: @Vector(3, f64) = try vec.unit(r.direction);
    const a: f64 = 0.5 * (unit_direction[1] + 1.0);
    return try vec.scale(init(1.0, 1.0, 1.0), 1.0 - a) + try vec.scale(init(0.5, 0.7, 1.0), a);
}

pub fn draw_ppm() !void {
    const stdout = std.io.getStdOut().writer();

    // Image
    const aspect_ratio: f64 = 16.0 / 9.0;
    const image_width: f64 = 400;

    // Caclulate the image height and ensure that it's at least one
    const image_height: f64 = if ((image_width / aspect_ratio) > 1) image_width / aspect_ratio else 1;

    // Camera
    const focal_length: f64 = 1.0;
    const viewport_height: f64 = 2.0;
    const viewport_width: f64 = viewport_height * @as(f64, image_width / image_height);
    const camera_center: @Vector(3, f64) = init(0, 0, 0);

    // Calculate the vectors across the horizontal and down the vertical viewport edges
    const viewport_u: @Vector(3, f64) = init(viewport_width, 0, 0);
    const viewport_v: @Vector(3, f64) = init(0, -viewport_height, 0);

    // Calculate the hoirzontal and vertical delta vectors pixel to pixel
    const pixel_delta_u: @Vector(3, f64) = viewport_u / init(image_width, image_width, image_width);
    const pixel_delta_v: @Vector(3, f64) = viewport_v / init(image_height, image_height, image_height);

    // Calculate the location of the upper left pixel
    const viewport_upper_left: @Vector(3, f64) = camera_center - init(0, 0, focal_length) - (viewport_u * init(0.5, 0.5, 0.5)) - (viewport_v * init(0.5, 0.5, 0.5));
    const pixel00_loc: @Vector(3, f64) = viewport_upper_left + init(0.5, 0.5, 0.5) * (pixel_delta_u + pixel_delta_v);

    // Render

    try stdout.print("P3\n{d} {d} \n255\n", .{ image_width, image_height });

    for (0..image_height) |j| {
        std.debug.print("\rScanlines remaining: {d}\n", .{image_height - @as(f64, @floatFromInt(j))});
        for (0..image_width) |i| {
            const f64_i: f64 = @as(f64, @floatFromInt(i));
            const f64_j: f64 = @as(f64, @floatFromInt(j));

            const pixel_center: @Vector(3, f64) = pixel00_loc + (init(f64_i, f64_i, f64_i) * pixel_delta_u) + (init(f64_j, f64_j, f64_j) * pixel_delta_v);
            const ray_direction: @Vector(3, f64) = pixel_center - camera_center;
            const r: ray.Ray = ray.Ray{ .origin = camera_center, .direction = ray_direction };

            const pixel_color: @Vector(3, f64) = try ray_color(r);
            try color.write_color(pixel_color);
            //const stdout = std.io.getStdOut().writer();
            //try stdout.print("{d} {d} {d}\n", .{ ir, ig, ib });
        }
    }

    std.debug.print("\rDone.              \n", .{});
}

pub fn main() !void {
    try draw_ppm();
}
