const rtw = @import("rtweekend.zig");

const Interval = rtw.interval.Interval;
const std = rtw.std;
const Ray = rtw.ray.Ray;
const hit_record = rtw.hittable.hit_record;
const Sphere = rtw.sphere.Sphere;
const Quad = @import("quad.zig").Quad;
const Box = @import("box.zig").Box;
const Translate = @import("instance.zig").Translate;
const RotateY = @import("instance.zig").RotateY;
const Material = rtw.material.Material;
const Texture = @import("texture.zig").Texture;
const RTWImage = @import("rtw_stb_image.zig").RTWImage;
const ArrayList = std.ArrayList;
const MultiArrayList = std.MultiArrayList;
const AABB = @import("aabb.zig").AABB;
const BVHNode = @import("bvh.zig").BVHNode;
const Hittable = @import("bvh.zig").Hittable;
const vec = @import("vec.zig");

pub const Primitive = union(enum) {
    Sphere: Sphere,
    Quad: Quad,
    Box: Box,
    Translate: Translate,
    RotateY: RotateY,

    pub fn hit(self: Primitive, r: *const Ray, ray_t: Interval, rec: *hit_record) bool {
        switch (self) {
            .Sphere => |s| return s.hit(r, ray_t, rec),
            .Quad => |q| return q.hit(r, ray_t, rec),
            .Box => |b| return b.hit(r, ray_t, rec),
            .Translate => |t| return t.hit(r, ray_t, rec),
            .RotateY => |rY| return rY.hit(r, ray_t, rec),
        }
    }

    pub fn boundingBox(self: Primitive) AABB {
        switch (self) {
            .Sphere => |s| return s.bounding_box(),
            .Quad => |q| return q.bounding_box(),
            .Box => |b| return b.bounding_box(),
            .Translate => |t| return t.bounding_box(),
            .RotateY => |rY| return rY.bounding_box(),
        }
    }
};

pub const HittableList = struct {
    spheres: MultiArrayList(Sphere),
    quads: MultiArrayList(Quad),
    boxes: ArrayList(Box),
    translates: ArrayList(Translate),
    rotations: ArrayList(RotateY),
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
            .translates = ArrayList(Translate){},
            .rotations = ArrayList(RotateY){},
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
        self.translates.deinit(self.allocator);
        self.rotations.deinit(self.allocator);
        self.materials.deinit(self.allocator);
        self.textures.deinit(self.allocator);

        for (self.boxes.items) |*b| {
            b.deinit();
        }

        self.boxes.deinit(self.allocator);

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
            .Translate => |t| {
                try self.*.translates.append(self.allocator, t);
                self.bbox = AABB.merge(self.bbox, t.bounding_box());
            },
            .RotateY => |rY| {
                try self.*.rotations.append(self.allocator, rY);
                self.bbox = AABB.merge(self.bbox, rY.bounding_box());
            },
        }
        // Clear BVH since we've modified the object list
        if (self.bvh_root != null) {
            self.bvh_root.?.deinit(self.allocator);
            self.bvh_root = null;
        }
        return self;
    }

    pub fn hit(self: Self, r: Ray, ray_t: Interval, rec: *hit_record) !bool {
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
            //const oc = center - r.origin;
            const oc = current_center - r.origin;
            const a = vec.square_magnitude(r.direction);
            const h = vec.dot(r.direction, oc);
            const c = vec.square_magnitude(oc) - radius * radius;
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
            //const outward_normal = (rec.p - center) * @as(@Vector(3, f32), @splat(radius));

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

            const denom = vec.dot(normal, r.direction);

            // Parallel to plane check (approximate)
            if (@abs(denom) < 1e-8) continue;

            const t = (D - vec.dot(normal, r.origin)) / denom;

            // Check against current closest_so_far
            if (t < ray_t.min or t > closest_so_far) continue;

            // Determine if hit is within the Quad (interior check)
            const intersection = r.position(t);
            const planar_hitpoint_vec = intersection - Qs[i];

            const alpha = vec.dot(ws[i], vec.cross(planar_hitpoint_vec, vs[i]));
            const beta = vec.dot(ws[i], vec.cross(us[i], planar_hitpoint_vec));

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

        for (self.translates.items) |t| {
            if (t.hit(&r, Interval.init(ray_t.min, closest_so_far), rec)) {
                hit_anything = true;
                closest_so_far = rec.t;
            }
        }

        for (self.rotations.items) |rY| {
            if (rY.hit(&r, Interval.init(ray_t.min, closest_so_far), rec)) {
                hit_anything = true;
                closest_so_far = rec.t;
            }
        }

        return hit_anything;
    }

    pub fn boundingBox(self: Self) AABB {
        if (self.objects.len == 0) {
            return AABB.empty();
        }

        // If BVH exists, use its bounding box
        if (self.bvh_root != null) {
            return self.bvh_root.?.boundingBox();
        }

        var output_box = AABB.empty();

        for (0..self.objects.len) |i| {
            const sphere = self.objects.get(i);
            output_box = AABB.merge(output_box, sphere.boundingBox());
        }
        return output_box;
    }

    pub fn buildBVH(self: *Self) !void {
        if (self.bvh_root != null) {
            self.bvh_root.?.deinit(self.allocator);
            self.bvh_root = null;
        }

        const total_count = self.spheres.len + self.quads.len + self.boxes.items.len + self.translates.items.len + self.rotations.items.len;
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

        for (self.translates.items) |t| {
            primitives[idx] = Primitive{ .Translate = t };
            idx += 1;
        }

        for (self.rotations.items) |rY| {
            primitives[idx] = Primitive{ .RotateY = rY };
            idx += 1;
        }

        // Build BVH from the combined list
        const bvh_node = try BVHNode.initFromList(self.allocator, primitives);
        self.bvh_root = try Hittable.createFromBVH(self.allocator, bvh_node);
    }
};
