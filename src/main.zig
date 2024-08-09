const rtw = @import("rtweekend.zig");

const init = rtw.vec.init;
const Sphere = rtw.sphere.sphere;
const std = rtw.std;
const hittable_list = rtw.HittableList.HittableList;
const Camera = rtw.camera.Camera;

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
    cam.max_depth = 5;
    try cam.render(&world);
}

pub fn main() !void {
    try draw_ppm();
}
