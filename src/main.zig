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
    defer world.deinit();

    const material_ground = Material.lambertian(@Vector(3, f64){ 0.5, 0.5, 0.5 });
    const material2 = Material.lambertian(@Vector(3, f64){ 0.4, 0.2, 0.1 });
    //const material_left = Material.dielectric(1.00 / 1.33);
    const material1 = Material.dielectric(1.5);
    const material3 = Material.metal(@Vector(3, f64){ 0.7, 0.6, 0.5 }, 0.0);
    _ = try world.add(Sphere{ .center = init(4, 1, 0), .radius = 1.0, .mat = &material3 });
    _ = try world.add(Sphere{ .center = init(0, 1, 0), .radius = 1.0, .mat = &material1 });
    _ = try world.add(Sphere{ .center = init(-4, 1, 0), .radius = 1.0, .mat = &material2 });

    var a: f64 = 0;
    while (a < 11) : (a += 1) {
        var b: f64 = 0;
        while (b < 11) : (b += 1) {
            var choose_mat = rtw.random_double();
            choose_mat = rtw.random_double();
            const center: @Vector(3, f64) = @Vector(3, f64){ a + 0.9 * rtw.random_double(), 0.2, b + 0.9 * rtw.random_double() };
            if (try rtw.vec.magnitude(center - @Vector(3, f64){ 4.0, 0.2, 0.0 }) > 0.9) {
                //var sphere_material: Material = undefined;

                if (choose_mat < 0.8) {
                    const albedo: @Vector(3, f64) = rtw.vec.random_vec_range(0, 1) * rtw.vec.random_vec_range(0, 1);
                    const sphere_material = Material.lambertian(albedo);
                    _ = try world.add(Sphere{ .center = center, .radius = 0.2, .mat = &sphere_material });
                } else if (choose_mat < 0.95) {
                    const albedo = rtw.vec.random_vec_range(0.5, 1.0);
                    const fuzz = rtw.random_double_range(0, 0.5);
                    const sphere_material = Material.metal(albedo, fuzz);
                    _ = try world.add(Sphere{ .center = center, .radius = 0.2, .mat = &sphere_material });
                } else {
                    const sphere_material = Material.dielectric(1.5);
                    _ = try world.add(Sphere{ .center = center, .radius = 0.2, .mat = &sphere_material });
                }
            }
        }
    }

    _ = try world.add(Sphere{ .center = init(0.0, -1000, 0), .radius = 1000, .mat = &material_ground });
    // Camera
    var cam: Camera = undefined;
    cam.aspect_ratio = 16.0 / 9.0;
    cam.image_width = 400;
    cam.samples_per_pixel = 25;
    cam.max_depth = 10;

    cam.vfov = 20;
    cam.lookfrom = @Vector(3, f64){ 13, 2, 3 };
    cam.lookat = @Vector(3, f64){ 0, 0, 0 };
    cam.vup = @Vector(3, f64){ 0, 1, 0 };
    cam.defocus_angle = 0.6;
    cam.focus_dist = 10.0;

    //for (world.objects.items) |object| {
    //    std.debug.print("{any}\n", .{object.center});
    //}
    //std.debug.print("world = {any}\n", .{world.objects.items});
    try cam.render(&world);
}

pub fn main() !void {
    try draw_ppm();
}
