const rtw = @import("rtweekend.zig");

const init = rtw.vec.init;
const Sphere = rtw.sphere.sphere;
const std = rtw.std;
const hittable_list = rtw.HittableList.HittableList;
const Camera = rtw.camera.Camera;
const Material = rtw.material.Material;

pub fn draw_ppm() !void {

    //allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    // world
    var world = hittable_list.init(allocator);
    //const R: f64 = std.math.cos(std.math.pi / 4.0);
    const material_ground = Material.lambertian(@Vector(3, f64){ 0.8, 0.8, 0.0 });
    const material_center = Material.lambertian(@Vector(3, f64){ 0.1, 0.2, 0.5 });
    const material_left = Material.dielectric(1.00 / 1.33);
    const material_bubble = Material.dielectric(1.00 / 1.50);
    const material_right = Material.metal(@Vector(3, f64){ 0.8, 0.6, 0.2 }, 1.0);

    defer world.deinit();
    //_ = try world.add(Sphere{ .center = init(0.0, -100.5, -1.0), .radius = 100.0, .mat = &material_ground });
    _ = try world.add(Sphere{ .center = init(0.0, 0.0, -1.2), .radius = 0.5, .mat = &material_center });

    //_ = try world.add(Sphere{ .center = init(-1.0, 0.0, -1.0), .radius = 0.4, .mat = &material_bubble });
    _ = try world.add(Sphere{ .center = init(-1, 0, -1), .radius = 0.5, .mat = &material_left });
    _ = try world.add(Sphere{ .center = init(-1.0, 0.0, -1.0), .radius = 0.4, .mat = &material_bubble });
    _ = try world.add(Sphere{ .center = init(1.0, 0, -1), .radius = 0.5, .mat = &material_right });

    _ = try world.add(Sphere{ .center = init(0.0, -100.5, -1.0), .radius = 100.0, .mat = &material_ground });
    // Camera
    var cam: Camera = undefined;
    cam.aspect_ratio = 16.0 / 9.0;
    cam.image_width = 400;
    cam.samples_per_pixel = 100;
    cam.max_depth = 100;
    cam.vfov = 20;
    cam.lookfrom = @Vector(3, f64){ -2, 2, 1 };
    cam.lookat = @Vector(3, f64){ 0, 0, -1 };
    cam.vup = @Vector(3, f64){ 0, 1, 0 };
    cam.defocus_angle = 10.0;
    cam.focus_dist = 3.4;
    try cam.render(&world);
}

pub fn main() !void {
    try draw_ppm();
}
