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
        self.*.normal = if (self.*.front_face) outward_normal.* else math.invert(outward_normal.*);
    }
};

pub const HittableList = struct {
    spheres: MultiArrayList(Sphere),
    quads: MultiArrayList(Quad),
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
            .spheres = MultiArrayList(Sphere){},
            .quads = MultiArrayList(Quad){},
            .boxes = ArrayList(Box){},
            .constant_mediums = ArrayList(ConstantMedium){},
            .materials = ArrayList(Material){},
            .textures = ArrayList(Texture){},
            .images = ArrayList(RTWImage){},
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

        self.*.spheres.deinit(self.allocator);
        self.*.quads.deinit(self.allocator);
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
                try self.*.spheres.append(self.allocator, s);
                self.bbox = AABB.merge(self.bbox, s.bounding_box());
            },
            .Quad => |q| {
                try self.*.quads.append(self.allocator, q);
                self.bbox = AABB.merge(self.bbox, q.bounding_box());
            },
            .Box => |b| {
                try self.boxes.append(self.allocator, b);
                self.bbox = AABB.merge(self.bbox, b.bounding_box());
            },
            .ConstantMedium => |cm| {
                try self.*.constant_mediums.append(self.allocator, cm);
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
        // Use BVH if available
        if (self.bvh_root != null) {
            return self.bvh_root.?.hit(r, ray_t, rec);
        }

        var hit_anything = false;
        var closest_so_far = ray_t.max;

        // --- SoA OPTIMIZATION STARTS HERE ---

        // 1. Get slices for the specific fields we need for intersection
        const centers = self.spheres.items(.center);
        const radii = self.spheres.items(.radius);
        const inv_radii = self.spheres.items(.inv_radius);
        const mat_ids = self.spheres.items(.mat_id);

        // 2. Iterate by index
        for (0..self.spheres.len) |i| {
            const center = centers[i];
            const radius = radii[i];
            const inv_radius = inv_radii[i];

            // Perform Intersection Check (Inlined for speed)
            const current_center = center.position(r.tm);
            const oc = current_center - r.origin;
            const a = math.square_magnitude(r.direction);
            const h = math.dot(r.direction, oc);
            const c = math.square_magnitude(oc) - radius * radius;
            const discriminant = h * h - a * c;

            if (discriminant < 0) continue;

            const sqrt_discriminant = @sqrt(discriminant);
            const inv_a = 1.0 / a;

            var root = (h - sqrt_discriminant) * inv_a;
            if (root <= ray_t.min or root >= closest_so_far) {
                root = (h + sqrt_discriminant) * inv_a;
                if (root <= ray_t.min or root >= closest_so_far) {
                    continue;
                }
            }

            // 3. We have a hit! Update the record.
            closest_so_far = root;
            hit_anything = true;

            rec.t = root;
            rec.p = r.position(root);

            const outward_normal = (rec.p - current_center) * @as(@Vector(3, f32), @splat(inv_radius));
            rec.set_face_normal(&r, &outward_normal);

            // Only access the material ID array when we actually hit something
            rec.mat_id = mat_ids[i];
        }

        // --- QUAD SOA LOOP ---
        // Fetch separate slices for Quad components
        const Qs = self.quads.items(.Q);
        const us = self.quads.items(.u);
        const vs = self.quads.items(.v);
        const ws = self.quads.items(.w);
        const normals = self.quads.items(.normal);
        const Ds = self.quads.items(.D);
        const quad_mats = self.quads.items(.mat_id);

        for (0..self.quads.len) |i| {
            const normal = normals[i];
            const D = Ds[i];

            const denom = math.dot(normal, r.direction);

            // Parallel to plane check (approximate)
            if (@abs(denom) < 1e-8) continue;

            const t = (D - math.dot(normal, r.origin)) / denom;

            // Check against current closest_so_far
            if (t < ray_t.min or t > closest_so_far) continue;

            // Determine if hit is within the Quad (interior check)
            const intersection = r.position(t);
            const planar_hitpoint_vec = intersection - Qs[i];

            const alpha = math.dot(ws[i], math.cross(planar_hitpoint_vec, vs[i]));
            const beta = math.dot(ws[i], math.cross(us[i], planar_hitpoint_vec));

            const unit_interval = Interval.init(0, 1);
            if (!unit_interval.contains(alpha) or !unit_interval.contains(beta)) continue;

            // Valid Hit!
            closest_so_far = t;
            hit_anything = true;

            rec.t = t;
            rec.p = intersection;
            rec.mat_id = quad_mats[i];
            rec.u = alpha;
            rec.v = beta;
            rec.set_face_normal(&r, &normal);
        }

        for (self.boxes.items) |b| {
            if (b.hit(&r, Interval.init(ray_t.min, closest_so_far), rec)) {
                hit_anything = true;
                closest_so_far = rec.t;
            }
        }

        for (self.constant_mediums.items) |cm| {
            if (cm.hit(&r, Interval.init(ray_t.min, closest_so_far), rec)) {
                hit_anything = true;
                closest_so_far = rec.t;
            }
        }

        return hit_anything;
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

        const total_count = self.spheres.len + self.quads.len + self.boxes.items.len + self.constant_mediums.items.len;
        if (total_count == 0) return;

        // Allocate a temporary list to hold all primitives for BVH construction
        var primitives = try self.allocator.alloc(Primitive, total_count);
        defer self.allocator.free(primitives);

        var idx: usize = 0;

        // Copy Spheres
        for (0..self.spheres.len) |i| {
            primitives[idx] = Primitive{ .Sphere = self.spheres.get(i) };
            idx += 1;
        }

        // Copy Quads
        for (0..self.quads.len) |i| {
            primitives[idx] = Primitive{ .Quad = self.quads.get(i) };
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
};
