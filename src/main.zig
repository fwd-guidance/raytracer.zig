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

pub fn draw_ppm() !void {

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
    cam.samples_per_pixel = 10;
    try cam.render(&world);
}

pub fn main() !void {
    try draw_ppm();
}
