const rtw = @import("rtweekend.zig");
const std = rtw.std;

const Sphere = rtw.sphere.Sphere;
const HittableList = rtw.HittableList.HittableList;
const Camera = rtw.camera.Camera;
const Material = rtw.material.Material;
const init = rtw.vec.init;
const hittable_list = rtw.HittableList.HittableList;

pub fn draw_ppm() !void {
    const page = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(page);
    defer arena.deinit();
    const allocator = arena.allocator();

    // world
    var world = hittable_list.init(allocator);
    defer world.deinit();

    const material_ground = Material.lambertian(@Vector(3, f32){ 0.5, 0.5, 0.5 });
    const ground_id = try world.add_material(material_ground);

    const material1 = Material.dielectric(1.50);
    const material1_id = try world.add_material(material1);

    const material2 = Material.lambertian(@Vector(3, f32){ 0.4, 0.2, 0.1 });
    const material2_id = try world.add_material(material2);

    const material3 = Material.metal(@Vector(3, f32){ 0.7, 0.6, 0.5 }, 0.0);
    const material3_id = try world.add_material(material3);

    var a: f32 = -11;
    while (a < 11) : (a += 1) {
        var b: f32 = -11;
        while (b < 11) : (b += 1) {
            const choose_mat = rtw.random_double();
            const center: @Vector(3, f32) = @Vector(3, f32){ a + 0.9 * rtw.random_double(), 0.2, b + 0.9 * rtw.random_double() };
            if (rtw.vec.magnitude(center - @Vector(3, f32){ 4.0, 0.2, 0.0 }) > 0.9) {
                if (choose_mat < 0.8) {
                    //const center_two = center + init(0, rtw.random_double_range(0, 0.5), 0);
                    const albedo = (rtw.vec.random_vec_range(0.0, 1.0) * rtw.vec.random_vec_range(0.0, 1.0));
                    const sphere_material = Material.lambertian(albedo);
                    const sphere_material_id = try world.add_material(sphere_material);
                    _ = try world.add(Sphere.init(center, null, 0.2, sphere_material_id));
                } else if (choose_mat < 0.95) {
                    const albedo = rtw.vec.random_vec_range(0.5, 1.0);
                    const fuzz = rtw.random_double_range(0, 0.5);
                    const sphere_material = Material.metal(albedo, fuzz);
                    const sphere_material_id = try world.add_material(sphere_material);
                    _ = try world.add(Sphere.init(center, null, 0.2, sphere_material_id));
                } else {
                    const sphere_material = Material.dielectric(1.5);
                    const sphere_material_id = try world.add_material(sphere_material);
                    _ = try world.add(Sphere.init(center, null, 0.2, sphere_material_id));
                }
            }
        }
    }

    _ = try world.add(Sphere.init(init(0, 1, 0), null, 1.0, material1_id));
    _ = try world.add(Sphere.init(init(-4, 1, 0), null, 1.0, material2_id));
    _ = try world.add(Sphere.init(init(4, 1, 0), null, 1.0, material3_id));
    _ = try world.add(Sphere.init(init(0.0, -1000, 0), null, 1000, ground_id));

    try world.buildBVH();

    var cam: Camera = undefined;
    cam.aspect_ratio = 16.0 / 9.0;
    cam.image_width = 1600;
    cam.samples_per_pixel = 500;
    cam.max_depth = 50;

    cam.vfov = 20;
    cam.lookfrom = @Vector(3, f32){ 13, 2, 3 };
    cam.lookat = @Vector(3, f32){ 0, 0, 0 };
    cam.vup = @Vector(3, f32){ 0, 1, 0 };
    cam.defocus_angle = 0.6;
    cam.focus_dist = 10.0;

    try cam.render(&world);
}

pub fn main() !void {
    try draw_ppm();
}
