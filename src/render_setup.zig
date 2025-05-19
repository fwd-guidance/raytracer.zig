const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const shd = @import("shader.glsl.zig");
const rtw = @import("rtweekend.zig");
const Sphere = rtw.sphere.sphere;
const Material = rtw.material.Material;
const HittableList = rtw.HittableList.HittableList;
const BVHNode = @import("bvh.zig").BVHNode;
const AABB = @import("aabb.zig").AABB;
const Hittable = @import("bvh.zig").Hittable;
const HittableType = @import("bvh.zig").HittableType;

// Constants
const MAX_SPHERES = 500;
//const MAX_BVH_NODES = 1000;

// Struct to hold the scene configuration
pub const SceneConfig = struct {
    // Camera parameters
    samples_per_pixel: i32,
    max_depth: i32,
    aspect_ratio: f32,
    vfov: f32,
    defocus_angle: f32,
    focus_dist: f32,
    lookfrom: @Vector(3, f32),
    lookat: @Vector(3, f32),
    vup: @Vector(3, f32),

    // Spheres in the scene
    sphere_count: i32,
    spheres: []const Sphere,

    // BVH data
    //bvh_node_count: i32,
    //bvh_root: ?*BVHNode,
};

// Helper function to set up sphere data in the expected vec4 format
fn setupSphereData(scene: SceneConfig, params: *shd.FsParams) void {
    // Initialize with default values
    for (0..MAX_SPHERES) |i| {
        params.u_sphere_data_1[i] = .{ 0.0, 0.0, 0.0, 0.0 }; // center.xyz, radius
        params.u_sphere_data_2[i] = .{ 0.0, 0.0, 0.0, 0.0 }; // material_type, albedo.xyz
        params.u_sphere_data_3[i] = .{ 0.0, 0.0, 0.0, 0.0 }; // metal_fuzz, refraction_index, unused, unused
    }

    // Maximum number of spheres we can handle
    const count = @min(scene.spheres.len, MAX_SPHERES);

    // Fill in sphere data
    for (scene.spheres[0..count], 0..) |sphere, i| {
        // Sphere center and radius in first vec4
        params.u_sphere_data_1[i][0] = sphere.center[0]; // center.x
        params.u_sphere_data_1[i][1] = sphere.center[1]; // center.y
        params.u_sphere_data_1[i][2] = sphere.center[2]; // center.z
        params.u_sphere_data_1[i][3] = sphere.radius; // radius

        // Material properties split across two vec4s
        var mat_type: f32 = 0.0; // Default to Lambertian
        var albedo = @Vector(3, f32){ 0.5, 0.5, 0.5 }; // Default gray
        var metal_fuzz: f32 = 0.0;
        var refraction_index: f32 = 1.0;

        // Set material properties based on material type
        switch (sphere.mat) {
            .Lambertian => |lambertian| {
                mat_type = 0.0;
                albedo = lambertian.albedo;
            },
            .Metal => |metal| {
                mat_type = 1.0;
                albedo = metal.albedo;
                metal_fuzz = metal.fuzz;
            },
            .Dielectric => |dielectric| {
                mat_type = 2.0;
                refraction_index = dielectric.refraction_index;
            },
        }

        // Material type and albedo in second vec4
        params.u_sphere_data_2[i][0] = mat_type; // material_type
        params.u_sphere_data_2[i][1] = albedo[0]; // albedo.x
        params.u_sphere_data_2[i][2] = albedo[1]; // albedo.y
        params.u_sphere_data_2[i][3] = albedo[2]; // albedo.z

        // Additional material properties in third vec4
        params.u_sphere_data_3[i][0] = metal_fuzz; // metal_fuzz
        params.u_sphere_data_3[i][1] = refraction_index; // refraction_index
        params.u_sphere_data_3[i][2] = 0.0; // unused
        params.u_sphere_data_3[i][3] = 0.0; // unused
    }
}

// Initialize BVH data arrays
//fn initBvhNodeData(params: *shd.FsParams) void {
//    for (0..MAX_BVH_NODES) |i| {
//        params.u_bvh_nodes_min[i] = .{ 0.0, 0.0, 0.0, 0.0 }; // min bounds (xyz), left_index (w)
//        params.u_bvh_nodes_max[i] = .{ 0.0, 0.0, 0.0, 0.0 }; // max bounds (xyz), right_index (w)
//        params.u_bvh_nodes_info[i] = .{ 0.0, 0.0, 0.0, 0.0 }; // item_index (x), is_leaf (y), unused (zw)
//    }
//}

// Helper function to set up BVH node data
//fn setupBvhData(scene: SceneConfig, params: *shd.FsParams) void {
// Initialize with default values
//    initBvhNodeData(params);

// Return early if no BVH data is available
//    if (scene.bvh_root == null or scene.bvh_node_count == 0) {
//        return;
//    }

// Get the root node and set its data
//    const root = scene.bvh_root.?;

// Maximum number of BVH nodes we can handle
//    const max_nodes = @min(scene.bvh_node_count, MAX_BVH_NODES);

// Basic implementation - just set the root node data
//    const box = root.bbox;
//    params.u_bvh_nodes_min[0][0] = box.x.min;
//    params.u_bvh_nodes_min[0][1] = box.y.min;
//    params.u_bvh_nodes_min[0][2] = box.z.min;

//    params.u_bvh_nodes_max[0][0] = box.x.max;
//    params.u_bvh_nodes_max[0][1] = box.y.max;
//    params.u_bvh_nodes_max[0][2] = box.z.max;

// Set is_leaf flag (not a leaf if left and right are different)
//    const is_leaf = (root.left == root.right);

//    params.u_bvh_nodes_info[0][1] = if (is_leaf) 1.0 else 0.0;

// For a complete implementation, we'd traverse the BVH tree here
// But for now, we'll just indicate that BVH is available by setting node count
//    std.debug.print("Set up BVH root node (max nodes: {d})\n", .{max_nodes});
//}

// Setup function to create the shader parameters
pub fn setupShaderParams(scene: SceneConfig) shd.FsParams {
    var params: shd.FsParams = undefined;

    // Resolution (from application window)
    params.u_resolution = .{ sapp.widthf(), sapp.heightf(), 0.0, 0.0 };

    // Main rendering parameters
    params.u_params = .{
        @floatFromInt(scene.samples_per_pixel), // x: samples_per_pixel
        @floatFromInt(scene.max_depth), // y: max_depth
        scene.aspect_ratio, // z: aspect_ratio
        scene.vfov, // w: vfov
    };

    // Camera configuration
    params.u_camera_params = .{
        scene.defocus_angle, // x: defocus_angle
        scene.focus_dist, // y: focus_dist
        @floatFromInt(scene.sphere_count), // z: sphere_count
        //@floatFromInt(scene.bvh_node_count), // w: bvh_node_count
        0.0, //unused
    };

    // Camera position and orientation
    params.u_lookfrom = .{
        scene.lookfrom[0], // x
        scene.lookfrom[1], // y
        scene.lookfrom[2], // z
        0.0, // w (unused)
    };

    params.u_lookat = .{
        scene.lookat[0], // x
        scene.lookat[1], // y
        scene.lookat[2], // z
        0.0, // w (unused)
    };

    params.u_vup = .{
        scene.vup[0], // x
        scene.vup[1], // y
        scene.vup[2], // z
        0.0, // w (unused)
    };

    // Set up sphere data
    setupSphereData(scene, &params);

    // Set up BVH data
    //setupBvhData(scene, &params);

    return params;
}

// Count BVH nodes (simplified version)
//fn countBvhNodes(_: *BVHNode) i32 {
// For now, just return a count of 1 to indicate BVH is present
// A full implementation would traverse the tree
//    return 1;
//}

// Creates a scene configuration from a hittable list
pub fn createSceneFromHittableList(
    allocator: std.mem.Allocator,
    world: *const HittableList,
    camera_config: struct {
        samples_per_pixel: i32,
        max_depth: i32,
        aspect_ratio: f32,
        vfov: f32,
        defocus_angle: f32,
        focus_dist: f32,
        lookfrom: @Vector(3, f32),
        lookat: @Vector(3, f32),
        vup: @Vector(3, f32),
    },
) !SceneConfig {
    var scene = SceneConfig{
        .samples_per_pixel = camera_config.samples_per_pixel,
        .max_depth = camera_config.max_depth,
        .aspect_ratio = camera_config.aspect_ratio,
        .vfov = camera_config.vfov,
        .defocus_angle = camera_config.defocus_angle,
        .focus_dist = camera_config.focus_dist,
        .lookfrom = camera_config.lookfrom,
        .lookat = camera_config.lookat,
        .vup = camera_config.vup,
        .sphere_count = 0,
        .spheres = &[_]Sphere{},
        //.bvh_node_count = 0,
        //.bvh_root = null,
    };

    // Extract spheres from the world
    var spheres = std.ArrayList(Sphere).init(allocator);
    defer spheres.deinit();

    // Iterate through world objects (these are already spheres)
    for (world.objects.items) |sphere| {
        try spheres.append(sphere);
    }

    // Set the sphere count and make a copy of the sphere data
    scene.sphere_count = @intCast(spheres.items.len);
    scene.spheres = try allocator.dupe(Sphere, spheres.items);

    // Extract and set BVH data if available
    //    if (world.bvh_root != null) {
    // Check if the root is a BVH node type
    //        if (@as(HittableType, world.bvh_root.?.*) == .bvh_node) {
    //            const bvh_node = world.bvh_root.?.bvh_node;
    //            scene.bvh_root = bvh_node;
    //            scene.bvh_node_count = countBvhNodes(bvh_node);
    //            std.debug.print("BVH available for rendering\n", .{});
    //        }
    //    }

    return scene;
}
