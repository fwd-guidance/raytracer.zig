const vec = @import("vec.zig");
const init = @import("vec.zig").init;
const color = @import("color.zig");
const ray = @import("ray.zig");

const sphere = @import("sphere.zig");
const Sphere = sphere.sphere;

const std = @import("std");
const hittable = @import("hittable.zig");
const hit_record = hittable.hit_record;
const hittableList = @import("hittable_list.zig");
const hittable_list = hittableList.HittableList;
const interval = @import("interval.zig");
const Interval = interval.Interval;
const camera = @import("camera.zig");
const Camera = camera.Camera;

//pub fn hit_sphere(center: @Vector(3, f64), radius: f64, r: ray.Ray) !f64 {
//    const oc: @Vector(3, f64) = center - r.origin;
//    const a: f64 = try vec.square_magnitude(r.direction);
//    const h: f64 = try vec.dot(r.direction, oc);
//    const c: f64 = try vec.square_magnitude(oc) - radius * radius;
//    //std.debug.print("OLD oc = {},       a = {},        h = {},      c = {}\n", .{ oc, a, h, c });
//    const discriminant: f64 = h * h - a * c;
//    //std.debug.print("OLD DISCRIMINANT = {}\n", .{discriminant});
//    if (discriminant < 0) {
//        return -1.0;
//    } else {
//        //std.debug.print("OLD ROOT = {}", .{(h - std.math.sqrt(discriminant)) / a});
//        return (h - std.math.sqrt(discriminant)) / a;
//    }
//}

//pub fn og_ray_color(r: ray.Ray) !@Vector(3, f64) {
//    const t: f64 = try hit_sphere(init(0, 0, -1), 0.5, r);
//    if (t > 0.0) {
//        //std.debug.print("OLD\n", .{});
//        const N: @Vector(3, f64) = try vec.unit(try r.position(t) - init(0, 0, -1));
//        //std.debug.print("OLD = {any}\n", .{N});
//        return try vec.scale(init(N[0] + 1, N[1] + 1, N[2] + 1), 0.5);
//    }

//    const unit_direction: @Vector(3, f64) = try vec.unit(r.direction);
//    const a: f64 = 0.5 * (unit_direction[1] + 1.0);
//    return try vec.scale(init(1.0, 1.0, 1.0), 1.0 - a) + try vec.scale(init(0.5, 0.7, 1.0), a);
//}

//pub fn ray_color(r: ray.Ray, world: *hittable_list) !@Vector(3, f64) {
//    const rec: hit_record = undefined;
//    const result = (world.hit(r, Interval{ .min = 0, .max = std.math.inf(f64) }, @constCast(&rec)));
//    if (result.ok) {
//        //std.debug.print("NEW N = {}\n", .{try vec.scale(result.result + init(1.0, 1.0, 1.0), 0.5)});
//        return try vec.scale(result.result + init(1.0, 1.0, 1.0), 0.5);
//    }
//
//    const unit_direction: @Vector(3, f64) = try vec.unit(r.direction);
//    const a: f64 = 0.5 * unit_direction[1] + 1.0;
//    return try vec.scale(init(1.0, 1.0, 1.0), 1.0 - a) + try vec.scale(init(0.5, 0.7, 1.0), a);
//}

pub fn draw_ppm() !void {
    //const stdout = std.io.getStdOut().writer();

    // Image
    //const aspect_ratio: f64 = 16.0 / 9.0;
    //const image_width: f64 = 400;

    // Caclulate the image height and ensure that it's at least one
    //const image_height: f64 = if ((image_width / aspect_ratio) > 1) image_width / aspect_ratio else 1;

    //allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    // world
    var world = hittable_list.init(allocator);
    defer world.deinit();
    _ = try world.add(Sphere{ .center = init(0, 0, -1), .radius = 0.5 });
    _ = try world.add(Sphere{ .center = init(0, -100.5, -1), .radius = 100 });

    // Camera
    var cam: Camera = undefined;
    cam.aspect_ratio = 16.0 / 9.0;
    cam.image_width = 400;
    try cam.render(&world);

    //const focal_length: f64 = 1.0;
    //const viewport_height: f64 = 2.0;
    //const viewport_width: f64 = viewport_height * @as(f64, image_width / image_height);
    //const camera_center: @Vector(3, f64) = init(0, 0, 0);

    // Calculate the vectors across the horizontal and down the vertical viewport edges
    //const viewport_u: @Vector(3, f64) = init(viewport_width, 0, 0);
    //const viewport_v: @Vector(3, f64) = init(0, -viewport_height, 0);

    // Calculate the hoirzontal and vertical delta vectors pixel to pixel
    //const pixel_delta_u: @Vector(3, f64) = viewport_u / init(image_width, image_width, image_width);
    //const pixel_delta_v: @Vector(3, f64) = viewport_v / init(image_height, image_height, image_height);

    // Calculate the location of the upper left pixel
    //const viewport_upper_left: @Vector(3, f64) = camera_center - init(0, 0, focal_length) - (viewport_u * init(0.5, 0.5, 0.5)) - (viewport_v * init(0.5, 0.5, 0.5));
    //const pixel00_loc: @Vector(3, f64) = viewport_upper_left + init(0.5, 0.5, 0.5) * (pixel_delta_u + pixel_delta_v);

    // Render

    //try stdout.print("P3\n{d} {d} \n255\n", .{ image_width, image_height });

    //for (0..image_height) |j| {
    //    //std.debug.print("\rScanlines remaining: {d}\n", .{image_height - @as(f64, @floatFromInt(j))});
    //    for (0..image_width) |i| {
    //        const f64_i: f64 = @as(f64, @floatFromInt(i));
    //        const f64_j: f64 = @as(f64, @floatFromInt(j));

    //        const pixel_center: @Vector(3, f64) = pixel00_loc + (init(f64_i, f64_i, f64_i) * pixel_delta_u) + (init(f64_j, f64_j, f64_j) * pixel_delta_v);
    //        const ray_direction: @Vector(3, f64) = pixel_center - camera_center;
    //        const r: ray.Ray = ray.Ray{ .origin = camera_center, .direction = ray_direction };

    //        const new_pixel_color: @Vector(3, f64) = try ray_color(r, @constCast(&world)); //@constCast(&world);
    //_ = new_pixel_color + init(1, 1, 1);
    //std.debug.print("NEW PIXEL COLOR = {}\n", .{new_pixel_color});
    //        try color.write_color(new_pixel_color);

    //const old_pixel_color: @Vector(3, f64) = try og_ray_color(r);
    //_ = old_pixel_color + init(1, 1, 1);
    //std.debug.print("OLD PIXEL COLOR = {}\n", .{old_pixel_color});
    //try color.write_color(old_pixel_color);
    //    }
    //}

    //std.debug.print("\rDone.              \n", .{});
    //std.debug.print("World: {any}\n", .{world.objects.items});
}

pub fn main() !void {
    try draw_ppm();
}
