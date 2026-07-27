const std = @import("std");
const math = @import("math.zig");
const p = @import("primitives.zig");
const Material = @import("material.zig").Material;
const Texture = @import("texture.zig").Texture;
const utils = @import("utils.zig");
const spatial = @import("spatial.zig");

const Hittable = spatial.Hittable;
const AABB = spatial.AABB;
const BVHNode = spatial.BVHNode;
const Primitive = p.Primitive;
const Interval = math.Interval;
const RTWImage = utils.RTWImage;

const Ray = math.Ray;
const MultiArrayList = std.MultiArrayList;
const ArrayList = std.ArrayList;
const Sphere = p.Sphere;
const Box = p.Box;
const Quad = p.Quad;
const ConstantMedium = p.ConstantMedium;

pub const HitRecord = struct {
    p: @Vector(3, f32),
    t: f32,
    u: f32,
    v: f32,
    mat_id: usize,
    normal: @Vector(3, f32),
    front_face: bool,

    pub fn set_face_normal(self: *HitRecord, r: *const Ray, outward_normal: *const @Vector(3, f32)) void {
        // Sets the hit record normal Vector
        // NOTE: the parameter outward_normal is assumed to have unit length

        self.*.front_face = (math.dot(r.direction, outward_normal.*)) < 0;
        self.*.normal = if (self.*.front_face) outward_normal.* else -(outward_normal.*);
    }
};

pub const HittableList = struct {
    spheres: ArrayList(Sphere),
    quads: ArrayList(Quad),
    boxes: ArrayList(Box),
    constant_mediums: ArrayList(ConstantMedium),
    materials: ArrayList(Material),
    textures: ArrayList(Texture),
    images: ArrayList(RTWImage),
    bvh_root: ?*Hittable, // Optional BVH root node
    bbox: AABB,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) HittableList {
        return .{
            .spheres = .empty,
            .quads = .empty,
            .boxes = .empty,
            .constant_mediums = .empty,
            .materials = .empty,
            .textures = .empty,
            .images = .empty,
            .bvh_root = null,
            .bbox = AABB.empty(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HittableList) void {
        // Free BVH if it exists
        if (self.bvh_root != null) {
            self.bvh_root.?.deinit(self.allocator);
            self.bvh_root = null;
        }

        self.spheres.deinit(self.allocator);
        self.quads.deinit(self.allocator);
        self.materials.deinit(self.allocator);
        self.textures.deinit(self.allocator);
        self.boxes.deinit(self.allocator);

        for (self.constant_mediums.items) |*cm| {
            cm.deinit();
        }

        self.constant_mediums.deinit(self.allocator);

        for (self.images.items) |*img| {
            img.deinit();
        }

        self.images.deinit(self.allocator);
    }

    pub fn add_image(self: *HittableList, img: RTWImage) !usize {
        try self.images.append(self.allocator, img);
        return self.images.items.len - 1;
    }

    pub fn add_texture(self: *HittableList, tex: Texture) !usize {
        try self.textures.append(self.allocator, tex);
        return self.textures.items.len - 1;
    }

    pub fn add_material(self: *HittableList, mat: Material) !usize {
        try self.materials.append(self.allocator, mat);
        return self.materials.items.len - 1;
    }

    pub fn add(self: *HittableList, obj: Primitive) anyerror!*HittableList {
        switch (obj) {
            .Sphere => |s| {
                try self.spheres.append(self.allocator, s);
                const stored = &self.spheres.items[self.spheres.items.len - 1];
                self.bbox = AABB.merge(self.bbox, stored.sphere_bounding_box().*);
            },
            .Quad => |q| {
                try self.quads.append(self.allocator, q);
                const stored = &self.quads.items[self.quads.items.len - 1];
                self.bbox = AABB.merge(self.bbox, stored.quad_bounding_box().*);
            },
            .Box => |b| {
                try self.boxes.append(self.allocator, b);
                const stored = &self.boxes.items[self.boxes.items.len - 1];
                self.bbox = AABB.merge(self.bbox, stored.box_bounding_box().*);
            },
            .ConstantMedium => |cm| {
                try self.constant_mediums.append(self.allocator, cm);
                const stored = &self.constant_mediums.items[self.constant_mediums.items.len - 1];
                self.bbox = AABB.merge(self.bbox, stored.constmed_bounding_box().*);
            },
        }
        // Clear BVH since we've modified the object list
        if (self.bvh_root != null) {
            self.bvh_root.?.deinit(self.allocator);
            self.bvh_root = null;
        }
        return self;
    }

    pub fn hl_hit(self: *const HittableList, r: *const Ray, ray_t: Interval, rec: *HitRecord) bool {
        return self.bvh_root.?.hittable_hit(r, ray_t, rec);
    }

    pub fn bounding_box(self: *HittableList) *const AABB {
        // If BVH exists, its box covers the whole scene.
        if (self.bvh_root) |root| {
            return root.bounding_box();
        }

        return &self.bbox;
    }

    pub fn build_bvh(self: *HittableList) !void {
        if (self.bvh_root != null) {
            self.bvh_root.?.deinit(self.allocator);
            self.bvh_root = null;
        }

        const total_count = self.spheres.items.len + self.quads.items.len + self.boxes.items.len + self.constant_mediums.items.len;
        if (total_count == 0) return;

        // Allocate a temporary list to hold all primitives for BVH construction
        var primitives = try self.allocator.alloc(Primitive, total_count);
        defer self.allocator.free(primitives);

        var idx: usize = 0;

        for (self.spheres.items) |s| {
            primitives[idx] = Primitive{ .Sphere = s };
            idx += 1;
        }

        for (self.quads.items) |q| {
            primitives[idx] = Primitive{ .Quad = q };
            idx += 1;
        }
        for (self.boxes.items) |b| {
            primitives[idx] = Primitive{ .Box = b };
            idx += 1;
        }

        for (self.constant_mediums.items) |cm| {
            primitives[idx] = Primitive{ .ConstantMedium = cm };
            idx += 1;
        }

        // Build BVH from the combined list
        const bvh_node = try BVHNode.init_from_list(self.allocator, primitives);
        self.bvh_root = try Hittable.create_from_bvh(self.allocator, bvh_node);
    }

    pub fn pdf_value(self: *const HittableList, origin: @Vector(3, f32), direction: @Vector(3, f32)) f32 {
        const n_spheres = self.spheres.items.len;
        const n_quads = self.quads.items.len;
        const n_boxes = self.boxes.items.len;
        const n_mediums = self.constant_mediums.items.len;
        const count = n_spheres + n_quads + n_boxes + n_mediums;
        if (count == 0) return 0;

        // Fast path: with a single light (the common case -- Cornell box),
        // weight = 1/count = 1, so skip the weight division and four loops
        // and dispatch directly.
        if (count == 1) {
            if (n_spheres == 1) return self.spheres.items[0].sphere_pdf_value(origin, direction);
            if (n_quads == 1) return self.quads.items[0].quad_pdf_value(origin, direction);
            if (n_boxes == 1) return self.boxes.items[0].box_pdf_value(origin, direction);
            return self.constant_mediums.items[0].constmed_pdf_value(origin, direction);
        }

        const weight = 1.0 / math.tof32(count);
        var sum: f32 = 0.0;

        for (self.spheres.items) |*s| {
            sum += weight * s.sphere_pdf_value(origin, direction);
        }

        for (self.quads.items) |*q| {
            sum += weight * q.quad_pdf_value(origin, direction);
        }

        for (self.boxes.items) |*b| {
            sum += weight * b.box_pdf_value(origin, direction);
        }

        for (self.constant_mediums.items) |*cm| {
            sum += weight * cm.constmed_pdf_value(origin, direction);
        }

        return sum;
    }

    pub fn random(self: *const HittableList, origin: @Vector(3, f32)) @Vector(3, f32) {
        const total = self.spheres.items.len +
            self.quads.items.len +
            self.boxes.items.len +
            self.constant_mediums.items.len;

        // Fast path: a single light needs no selection draw (saves one RNG
        // call per light-sampled bounce) and no index walk.
        if (total == 1) {
            if (self.spheres.items.len == 1) return self.spheres.items[0].sphere_random(origin);
            if (self.quads.items.len == 1) return self.quads.items[0].quad_random(origin);
            if (self.boxes.items.len == 1) return self.boxes.items[0].box_random(origin);
            return self.constant_mediums.items[0].constmed_random(origin);
        }

        const index: usize = @intCast(utils.random_int(0, math.tof32(total) - 1));

        if (index < self.spheres.items.len) {
            return self.spheres.items[index].sphere_random(origin);
        }
        const after_spheres = self.spheres.items.len;
        if (index < after_spheres + self.quads.items.len) {
            return self.quads.items[index - after_spheres].quad_random(origin);
        }
        const after_quads = after_spheres + self.quads.items.len;
        if (index < after_quads + self.boxes.items.len) {
            return self.boxes.items[index - after_quads].box_random(origin);
        }
        return self.constant_mediums.items[index - after_quads - self.boxes.items.len].constmed_random(origin);
    }
};
