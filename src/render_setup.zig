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
const MAX_BVH_NODES = 1000;

const BVHNodeData = struct {
    bbox_min: @Vector(3, f32),
    bbox_max: @Vector(3, f32),
    left_index: i32,
    right_index: i32,
    hittable_type: i32, // 0 = sphere, 1 = bvh_node
    hittable_index: i32, // For leaf nodes, index into sphere array
};

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
    bvh_node_count: i32,
    bvh_nodes: []BVHNodeData,
    bvh_root: ?*Hittable,
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
fn initBvhNodeData(params: *shd.FsParams) void {
    for (0..MAX_BVH_NODES) |i| {
        params.u_bvh_data_1[i] = .{ 0.0, 0.0, 0.0, -1.0 }; // bbox_min.xyz, left_index (w)
        params.u_bvh_data_2[i] = .{ 0.0, 0.0, 0.0, -1.0 }; // bbox_max.xyz, right_index (w)
        params.u_bvh_data_3[i] = .{ 0.0, -1.0, 0.0, 0.0 }; // hittable_type, hittable_index, unused
    }
}

// Helper function to set up BVH node data
fn setupBvhData(scene: SceneConfig, params: *shd.FsParams) void {
    // Initialize with default values
    initBvhNodeData(params);

    // Return early if no BVH data is available
    if (scene.bvh_nodes.len == 0) {
        return;
    }

    // Maximum number of BVH nodes we can handle
    const max_nodes = @min(scene.bvh_nodes.len, MAX_BVH_NODES);

    // Copy BVH node data to shader parameters
    for (scene.bvh_nodes[0..max_nodes], 0..) |node, i| {
        // Bounding box min and left child index
        params.u_bvh_data_1[i][0] = node.bbox_min[0];
        params.u_bvh_data_1[i][1] = node.bbox_min[1];
        params.u_bvh_data_1[i][2] = node.bbox_min[2];
        params.u_bvh_data_1[i][3] = @floatFromInt(node.left_index);

        // Bounding box max and right child index
        params.u_bvh_data_2[i][0] = node.bbox_max[0];
        params.u_bvh_data_2[i][1] = node.bbox_max[1];
        params.u_bvh_data_2[i][2] = node.bbox_max[2];
        params.u_bvh_data_2[i][3] = @floatFromInt(node.right_index);

        // Hittable type and index
        params.u_bvh_data_3[i][0] = @floatFromInt(node.hittable_type);
        params.u_bvh_data_3[i][1] = @floatFromInt(node.hittable_index);
        params.u_bvh_data_3[i][2] = 0.0; // unused
        params.u_bvh_data_3[i][3] = 0.0; // unused
    }

    std.debug.print("Set up {} BVH nodes for GPU\n", .{max_nodes});
}

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
        @floatFromInt(scene.bvh_node_count), // w: bvh_node_count
        //0.0, //unused
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
    setupBvhData(scene, &params);

    return params;
}

// Recursively serialize BVH tree into a flat array
fn serializeBvhNode(
    allocator: std.mem.Allocator,
    hittable: *Hittable,
    nodes: *std.ArrayList(BVHNodeData),
    sphere_map: std.AutoHashMap(*const Sphere, usize),
) !i32 {
    const node_index = @as(i32, @intCast(nodes.items.len));

    switch (hittable.*) {
        .sphere => |*sphere| {
            // Leaf node containing a sphere
            const bbox = sphere.boundingBox();
            const sphere_index = sphere_map.get(sphere) orelse {
                std.debug.print("Warning: sphere not found in map\n", .{});
                return -1;
            };

            try nodes.append(.{
                .bbox_min = .{ bbox.x.min, bbox.y.min, bbox.z.min },
                .bbox_max = .{ bbox.x.max, bbox.y.max, bbox.z.max },
                .left_index = -1,
                .right_index = -1,
                .hittable_type = 0, // HITTABLE_SPHERE
                .hittable_index = @intCast(sphere_index),
            });
        },
        .bvh_node => |bvh| {
            // Internal BVH node
            const bbox = bvh.bbox;

            // Reserve space for this node
            try nodes.append(.{
                .bbox_min = .{ bbox.x.min, bbox.y.min, bbox.z.min },
                .bbox_max = .{ bbox.x.max, bbox.y.max, bbox.z.max },
                .left_index = -1, // Will be filled in
                .right_index = -1, // Will be filled in
                .hittable_type = 1, // HITTABLE_BVH_NODE
                .hittable_index = -1,
            });

            // Recursively serialize children
            const left_index = try serializeBvhNode(allocator, bvh.left, nodes, sphere_map);
            const right_index = try serializeBvhNode(allocator, bvh.right, nodes, sphere_map);

            // Update the node with child indices
            nodes.items[@intCast(node_index)].left_index = left_index;
            nodes.items[@intCast(node_index)].right_index = right_index;
        },
    }

    return node_index;
}

fn collectSpheresFromBVH(hittable: *Hittable, spheres: *std.ArrayList(*const Sphere)) !void {
    switch (hittable.*) {
        .sphere => |*sphere| {
            try spheres.append(sphere);
        },
        .bvh_node => |bvh| {
            try collectSpheresFromBVH(bvh.left, spheres);
            if (bvh.left != bvh.right) {
                try collectSpheresFromBVH(bvh.right, spheres);
            }
        },
    }
}

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
        .bvh_node_count = 0,
        .bvh_nodes = &[_]BVHNodeData{},
        .bvh_root = null,
    };

    // Use the original world objects as our sphere list
    scene.sphere_count = @intCast(world.objects.items.len);
    scene.spheres = try allocator.dupe(Sphere, world.objects.items);

    std.debug.print("Scene has {} spheres from world objects\n", .{scene.sphere_count});

    // Extract and serialize BVH data if available
    if (world.bvh_root) |bvh_root| {
        scene.bvh_root = bvh_root;

        // Create a map from sphere pointers in BVH to indices in our sphere array
        var sphere_map = std.AutoHashMap(*const Sphere, usize).init(allocator);
        defer sphere_map.deinit();

        // Collect all sphere pointers from the BVH
        var sphere_ptrs = std.ArrayList(*const Sphere).init(allocator);
        defer sphere_ptrs.deinit();
        try collectSpheresFromBVH(bvh_root, &sphere_ptrs);

        std.debug.print("BVH contains {} sphere references\n", .{sphere_ptrs.items.len});

        // Map BVH sphere pointers to indices in world.objects
        for (sphere_ptrs.items) |bvh_sphere_ptr| {
            // Find matching sphere in world objects by comparing values
            for (world.objects.items, 0..) |world_sphere, idx| {
                // Compare by position and radius (should be unique enough)
                if (@reduce(.And, bvh_sphere_ptr.center == world_sphere.center) and
                    bvh_sphere_ptr.radius == world_sphere.radius)
                {
                    try sphere_map.put(bvh_sphere_ptr, idx);
                    break;
                }
            }
        }

        // Serialize the BVH tree into a flat array
        var bvh_nodes = std.ArrayList(BVHNodeData).init(allocator);
        defer bvh_nodes.deinit();

        _ = try serializeBvhNode(allocator, bvh_root, &bvh_nodes, sphere_map);

        scene.bvh_node_count = @intCast(bvh_nodes.items.len);
        scene.bvh_nodes = try allocator.dupe(BVHNodeData, bvh_nodes.items);

        std.debug.print("BVH serialized: {} nodes for {} spheres\n", .{ scene.bvh_node_count, scene.sphere_count });
    }

    return scene;
}
