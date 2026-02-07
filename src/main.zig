const rtw = @import("rtweekend.zig");
const RTWImage = @import("rtw_stb_image.zig").RTWImage;
const std = rtw.std;

const Sphere = rtw.sphere.Sphere;
const HittableList = rtw.HittableList.HittableList;
const Camera = rtw.camera.Camera;
const Material = rtw.material.Material;
const Texture = @import("texture.zig").Texture;
const init = rtw.vec.init;
const hittable_list = rtw.HittableList.HittableList;
const Perlin = @import("perlin.zig").Perlin;

pub fn draw_perlin_spheres() !void {
    const page = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(page);
    defer arena.deinit();
    const allocator = arena.allocator();

    var world = hittable_list.init(allocator);
    defer world.deinit();

    const noise_tex = Texture.noise(4);
    const noise_tex_id = try world.add_texture(noise_tex);
    const perlin_material = Material.lambertian(noise_tex_id);
    const perlin_material_id = try world.add_material(perlin_material);

    _ = try world.add(Sphere.init(init(0, -1000, 0), null, 1000, perlin_material_id));
    _ = try world.add(Sphere.init(init(0, 2, 0), null, 2, perlin_material_id));

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
    cam.defocus_angle = 0.0;
    cam.focus_dist = 10.0;

    try cam.render(&world);
}

pub fn draw_checkered_spheres() !void {
    const page = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(page);
    defer arena.deinit();
    const allocator = arena.allocator();

    var world = hittable_list.init(allocator);
    defer world.deinit();

    //const material_ground = Material.lambertian(@Vector(3, f32){ 0.5, 0.5, 0.5 });
    const white_tex = Texture.solid_color(@Vector(3, f32){ 0.9, 0.9, 0.9 });
    const white_id = try world.add_texture(white_tex);

    const green_tex = Texture.solid_color(@Vector(3, f32){ 0.2, 0.3, 0.1 });
    const green_id = try world.add_texture(green_tex);

    // Create checker from the solid colors
    const checker_tex = Texture.checker(0.32, &world.textures.items[white_id], &world.textures.items[green_id]);
    const checker_id = try world.add_texture(checker_tex);

    const material_ground = Material.lambertian(checker_id);
    const ground_id = try world.add_material(material_ground);

    _ = try world.add(Sphere.init(init(0, -10, 0), null, 10, ground_id));
    _ = try world.add(Sphere.init(init(0, 10, 0), null, 10, ground_id));

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
    cam.defocus_angle = 0.0;
    cam.focus_dist = 10.0;

    try cam.render(&world);
}

pub fn draw_earth() !void {
    const page = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(page);
    defer arena.deinit();
    const allocator = arena.allocator();

    var world = hittable_list.init(allocator);
    defer world.deinit();

    // Load an image
    const earth_image = try RTWImage.init_from_file(allocator, "earthmap.jpg");
    const earth_img_id = try world.add_image(earth_image);

    // Create an image texture from it
    const earth_texture = Texture.image(&world.images.items[earth_img_id]);
    const earth_tex_id = try world.add_texture(earth_texture);

    // Create a lambertian material with the image texture
    const earth_material = Material.lambertian(earth_tex_id);
    const earth_mat_id = try world.add_material(earth_material);

    _ = try world.add(Sphere.init(init(0, 0, 0), null, 2.0, earth_mat_id));

    try world.buildBVH();

    var cam: Camera = undefined;
    cam.aspect_ratio = 16.0 / 9.0;
    cam.image_width = 1600;
    cam.samples_per_pixel = 500;
    cam.max_depth = 50;

    cam.vfov = 20;
    cam.lookfrom = @Vector(3, f32){ 0, 0, 12 };
    cam.lookat = @Vector(3, f32){ 0, 0, 0 };
    cam.vup = @Vector(3, f32){ 0, 1, 0 };
    cam.defocus_angle = 0.0;
    cam.focus_dist = 10.0;

    try cam.render(&world);
}

pub fn draw_ppm() !void {
    const page = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(page);
    defer arena.deinit();
    const allocator = arena.allocator();

    var world = hittable_list.init(allocator);
    defer world.deinit();

    // create white and green checker texture
    const white_tex = Texture.solid_color(@Vector(3, f32){ 0.9, 0.9, 0.9 });
    const white_id = try world.add_texture(white_tex);
    const green_tex = Texture.solid_color(@Vector(3, f32){ 0.2, 0.3, 0.1 });
    const green_id = try world.add_texture(green_tex);
    const checker_tex = Texture.checker(0.32, &world.textures.items[white_id], &world.textures.items[green_id]);
    const checker_id = try world.add_texture(checker_tex);
    const material_ground = Material.lambertian(checker_id);
    const ground_id = try world.add_material(material_ground);

    const material1 = Material.dielectric(1.50);
    const material1_id = try world.add_material(material1);

    const brown_tex = Texture.solid_color(@Vector(3, f32){ 0.4, 0.2, 0.1 });
    const brown_tex_id = try world.add_texture(brown_tex);
    const material2 = Material.lambertian(brown_tex_id);
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

                    const sphere_tex = Texture.solid_color(albedo);
                    const sphere_tex_id = try world.add_texture(sphere_tex);

                    const sphere_material = Material.lambertian(sphere_tex_id);
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
    //try draw_ppm();
    //try draw_checkered_spheres();
    //try draw_earth();
    try draw_perlin_spheres();
}
