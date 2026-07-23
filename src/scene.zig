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
    const Self = @This();

    pub fn set_face_normal(self: *Self, r: *const Ray, outward_normal: *const @Vector(3, f32)) void {
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

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
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

    pub fn deinit(self: *Self) void {
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

    pub fn add_image(self: *Self, img: RTWImage) !usize {
        try self.images.append(self.allocator, img);
        return self.images.items.len - 1;
    }

    pub fn add_texture(self: *Self, tex: Texture) !usize {
        try self.textures.append(self.allocator, tex);
        return self.textures.items.len - 1;
    }

    pub fn add_material(self: *Self, mat: Material) !usize {
        try self.materials.append(self.allocator, mat);
        return self.materials.items.len - 1;
    }

    pub fn add(self: *Self, obj: Primitive) anyerror!*Self {
        switch (obj) {
            .Sphere => |s| {
                try self.spheres.append(self.allocator, s);
                self.bbox = AABB.merge(self.bbox, s.bounding_box());
            },
            .Quad => |q| {
                try self.quads.append(self.allocator, q);
                self.bbox = AABB.merge(self.bbox, q.bounding_box());
            },
            .Box => |b| {
                try self.boxes.append(self.allocator, b);
                self.bbox = AABB.merge(self.bbox, b.bounding_box());
            },
            .ConstantMedium => |cm| {
                try self.constant_mediums.append(self.allocator, cm);
                self.bbox = AABB.merge(self.bbox, cm.bounding_box());
            },
        }
        // Clear BVH since we've modified the object list
        if (self.bvh_root != null) {
            self.bvh_root.?.deinit(self.allocator);
            self.bvh_root = null;
        }
        return self;
    }

    pub fn hit(self: Self, r: Ray, ray_t: Interval, rec: *HitRecord) !bool {
        return self.bvh_root.?.hit(r, ray_t, rec);
    }

    pub fn bounding_box(self: Self) AABB {
        if (self.objects.len == 0) {
            return AABB.empty();
        }

        // If BVH exists, use its bounding box
        if (self.bvh_root != null) {
            return self.bvh_root.?.bounding_box();
        }

        var output_box = AABB.empty();

        for (0..self.objects.len) |i| {
            const sphere = self.objects.get(i);
            output_box = AABB.merge(output_box, sphere.bounding_box());
        }
        return output_box;
    }

    pub fn build_bvh(self: *Self) !void {
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
        const weight = 1.0 / @as(f32, @floatFromInt(self.spheres.items.len + self.quads.items.len + self.boxes.items.len + self.constant_mediums.items.len));
        var sum: f32 = 0.0;

        for (self.spheres.items) |s| {
            sum += weight * s.pdf_value(origin, direction);
        }

        for (self.quads.items) |q| {
            sum += weight * q.pdf_value(origin, direction);
        }

        for (self.boxes.items) |b| {
            sum += weight * b.pdf_value(origin, direction);
        }

        for (self.constant_mediums.items) |cm| {
            sum += weight * cm.pdf_value(origin, direction);
        }

        return sum;
    }

    pub fn random(self: *const HittableList, origin: @Vector(3, f32)) @Vector(3, f32) {
        const int_size = @as(f32, @floatFromInt(self.spheres.items.len + self.quads.items.len + self.boxes.items.len));
        var index: usize = @intCast(utils.random_int(0, int_size - 1));

        if (index < self.spheres.items.len) {
            return self.spheres.items[index].random(origin);
        } else if (index < (self.spheres.items.len + self.quads.items.len)) {
            index = index % self.spheres.items.len;
            return self.quads.items[index].random(origin);
        } else if (index < (self.spheres.items.len + self.quads.items.len + self.boxes.items.len)) {
            index = index % (self.spheres.items.len + self.quads.items.len + self.boxes.items.len);
            return self.boxes.items[index].random(origin);
        } else {
            index = index % (self.spheres.items.len + self.quads.items.len + self.boxes.items.len + self.constant_mediums.items.len);
            return self.constant_mediums.items[index].random(origin);
        }
    }
};
