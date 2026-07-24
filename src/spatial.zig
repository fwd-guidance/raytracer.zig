const std = @import("std");
const math = @import("math.zig");
const primitives = @import("primitives.zig");
const scene = @import("scene.zig");

const HitRecord = scene.HitRecord;
const Primitive = primitives.Primitive;
const Sphere = primitives.Sphere;
const Ray = math.Ray;
const Interval = math.Interval;

pub const AABB = struct {
    x: Interval,
    y: Interval,
    z: Interval,

    pub fn init(x: Interval, y: Interval, z: Interval) AABB {
        return pad(AABB{ .x = x, .y = y, .z = z });
    }

    pub fn empty() AABB {
        const empty_interval = Interval.empty();
        return AABB.init(empty_interval, empty_interval, empty_interval);
    }

    pub fn init_from_points(a: @Vector(3, f32), b: @Vector(3, f32)) AABB {
        // The bounding box containing both points
        const aabb = AABB{
            .x = Interval.init(@min(a[0], b[0]), @max(a[0], b[0])),
            .y = Interval.init(@min(a[1], b[1]), @max(a[1], b[1])),
            .z = Interval.init(@min(a[2], b[2]), @max(a[2], b[2])),
        };

        return pad(aabb);
    }

    pub fn add(self: AABB, offset: @Vector(3, f32)) AABB {
        return .{ .x = self.x.add(offset[0]), .y = self.y.add(offset[1]), .z = self.z.add(offset[2]) };
    }

    pub fn longest_axis(self: AABB) u8 {
        const x_size = self.x.size();
        const y_size = self.y.size();
        const z_size = self.z.size();

        if (x_size > y_size) {
            return if (x_size > z_size) 0 else 2;
        } else {
            return if (y_size > z_size) 1 else 2;
        }
    }

    pub fn pad(self: AABB) AABB {
        // Return a new bounding box that is slightly larger than the original
        const delta = 0.0001;
        const new_x = if (self.x.size() >= delta) self.x else self.x.expand(delta);
        const new_y = if (self.y.size() >= delta) self.y else self.y.expand(delta);
        const new_z = if (self.z.size() >= delta) self.z else self.z.expand(delta);

        return AABB{
            .x = new_x,
            .y = new_y,
            .z = new_z,
        };
    }

    pub fn merge(a: AABB, b: AABB) AABB {
        return AABB{
            .x = Interval.merge(a.x, b.x),
            .y = Interval.merge(a.y, b.y),
            .z = Interval.merge(a.z, b.z),
        };
    }

    pub fn hit(self: AABB, r: Ray, ray_t: Interval) bool {
        // For each dimension, compute the times the ray enters and exits the box
        var t_min = ray_t.min;
        var t_max = ray_t.max;

        // Loop over the three dimensions for x=0, y=1, z=2
        inline for (0..3) |dim| {
            const invD = r.inv_direction[dim];
            const orig = r.origin[dim];
            const interval = switch (dim) {
                0 => self.x,
                1 => self.y,
                2 => self.z,
                else => unreachable,
            };

            // Calculate intersection with current axis
            var t0 = (interval.min - orig) * invD;
            var t1 = (interval.max - orig) * invD;

            // If ray is traveling in negative direction, swap t0 and t1
            if (invD < 0.0) {
                const temp = t0;
                t0 = t1;
                t1 = temp;
            }

            // Update overall intersection interval
            t_min = @max(t0, t_min);
            t_max = @min(t1, t_max);

            if (t_max <= t_min) {
                return false; // No intersection with this box
            }
        }

        return true; // Ray intersects box
    }

    pub fn hit_distance(self: AABB, r: Ray, ray_t: Interval) ?f32 {
        const box_min = @Vector(3, f32){ self.x.min, self.y.min, self.z.min };
        const box_max = @Vector(3, f32){ self.x.max, self.y.max, self.z.max };

        const t0 = (box_min - r.origin) * r.inv_direction;
        const t1 = (box_max - r.origin) * r.inv_direction;

        // Handle NaNs by replacing them or ensuring the logic survives
        // A common trick is to use select to ensure t_smaller is always valid
        const t_smaller = @min(t0, t1);
        const t_bigger = @max(t0, t1);

        const t_min = @max(ray_t.min, @reduce(.Max, t_smaller));
        const t_max = @min(ray_t.max, @reduce(.Min, t_bigger));

        // STRICT inequality is dangerous for flat objects if t_min == t_max
        // Use <= instead of <
        if (t_min <= t_max) {
            return t_min;
        } else {
            return null;
        }
    }
};

pub const BVHNode = struct {
    left: *Hittable,
    right: *Hittable,
    bbox: AABB,

    // Construct a bounding volume hierarchy node from a range of hittables
    pub fn init_from_list(allocator: std.mem.Allocator, objects: []Primitive) !*BVHNode {
        return try init_from_span(allocator, objects, 0, objects.len);
    }

    pub fn init_from_span(allocator: std.mem.Allocator, objects: []Primitive, start: usize, end: usize) !*BVHNode {
        var node = try allocator.create(BVHNode);

        var span_bbox = AABB.empty();
        for (start..end) |i| {
            span_bbox = AABB.merge(span_bbox, objects[i].bounding_box());
        }
        const axis = span_bbox.longest_axis();

        const object_span = end - start;

        if (object_span == 1) {
            node.left = try create_hittable_from_primitive(allocator, objects[start]);
            node.right = node.left;
        } else if (object_span == 2) {
            if (box_compare(objects[start], objects[start + 1], axis)) {
                node.left = try create_hittable_from_primitive(allocator, objects[start]);
                node.right = try create_hittable_from_primitive(allocator, objects[start + 1]);
            } else {
                node.left = try create_hittable_from_primitive(allocator, objects[start + 1]);
                node.right = try create_hittable_from_primitive(allocator, objects[start]);
            }
        } else {
            sort_primitives_by_axis(objects[start..end], axis);

            const mid = start + object_span / 2;

            node.left = try Hittable.create_from_bvh(allocator, try init_from_span(allocator, objects, start, mid));
            node.right = try Hittable.create_from_bvh(allocator, try init_from_span(allocator, objects, mid, end));
        }

        const box_left = node.left.bounding_box();
        const box_right = node.right.bounding_box();
        node.bbox = AABB.merge(box_left, box_right);
        return node;
    }

    pub fn deinit(self: *BVHNode, allocator: std.mem.Allocator) void {
        self.left.deinit(allocator);
        if (self.right != self.left) { // Avoid double-freeing if both point to same object
            self.right.deinit(allocator);
        }
        allocator.destroy(self);
    }

    pub fn hit(self: BVHNode, r: Ray, ray_t: Interval, rec: *HitRecord) bool {
        // OPTIONAL: Check self.bbox first.
        // (Can be removed if you trust the parent logic, but safe to keep for root).
        //if (self.bbox.hit_distance(r, ray_t) == null) return false;

        // 1. Fetch children's bounding boxes
        const box_left = self.left.bounding_box();
        const box_right = self.right.bounding_box();

        // 2. Intersect both boxes to get distances
        const dist_left = box_left.hit_distance(r, ray_t);
        const dist_right = box_right.hit_distance(r, ray_t);

        // 3. Logic: Traverse the closer child first
        if (dist_left != null and dist_right != null) {
            if (dist_left.? < dist_right.?) {
                // Left is closer: Visit Left -> Right
                const hit_l = self.left.hit(r, ray_t, rec);

                // If left hit, it shrunk the search window (rec.t).
                // We use this tighter window for the right child.
                const t_max = if (hit_l) rec.t else ray_t.max;
                const right_interval = Interval.init(ray_t.min, t_max);

                const hit_r = self.right.hit(r, right_interval, rec);
                return hit_l or hit_r;
            } else {
                // Right is closer: Visit Right -> Left
                const hit_r = self.right.hit(r, ray_t, rec);

                const t_max = if (hit_r) rec.t else ray_t.max;
                const left_interval = Interval.init(ray_t.min, t_max);

                const hit_l = self.left.hit(r, left_interval, rec);
                return hit_r or hit_l;
            }
        } else if (dist_left != null) {
            // Only left box hit
            return self.left.hit(r, ray_t, rec);
        } else if (dist_right != null) {
            // Only right box hit
            return self.right.hit(r, ray_t, rec);
        } else {
            // Neither box hit
            return false;
        }
    }

    pub fn bounding_box(self: BVHNode) AABB {
        return self.bbox;
    }
};

// Helper function to compare two spheres by a given axis
fn box_compare(a: Primitive, b: Primitive, axis: u8) bool {
    const box_a = a.bounding_box();
    const box_b = b.bounding_box();

    switch (axis) {
        0 => return box_a.x.min < box_b.x.min, // x-axis
        1 => return box_a.y.min < box_b.y.min, // y-axis
        2 => return box_a.z.min < box_b.z.min, // z-axis
        else => @panic("Invalid axis"),
    }
}

// Helper function to sort primitives by a given axis.
// Uses pdq sort (O(n log n)) for large slices, falling back to insertion
// sort for small slices where the constant factor wins.
fn sort_primitives_by_axis(objects: []Primitive, axis: u8) void {
    const Context = struct {
        axis: u8,
        pub fn lessThan(self: @This(), a: Primitive, b: Primitive) bool {
            return box_compare(a, b, self.axis);
        }
    };

    if (objects.len <= 32) {
        std.sort.insertion(Primitive, objects, Context{ .axis = axis }, Context.lessThan);
    } else {
        std.sort.pdq(Primitive, objects, Context{ .axis = axis }, Context.lessThan);
    }
}

// Helper to create a hittable from a sphere
fn create_hittable_from_primitive(allocator: std.mem.Allocator, primitive: Primitive) !*Hittable {
    const hittable = try allocator.create(Hittable);
    hittable.* = Hittable{ .primitive = primitive };
    return hittable;
}

// A unified Hittable interface to handle different types
pub const HittableType = enum {
    primitive,
    bvh_node,
};

pub const Hittable = union(HittableType) {
    primitive: Primitive,
    bvh_node: *BVHNode,

    pub fn hit(self: Hittable, r: Ray, ray_t: Interval, rec: *HitRecord) bool {
        return switch (self) {
            .primitive => |p| p.hit(&r, ray_t, rec),
            .bvh_node => |b| b.hit(r, ray_t, rec),
        };
    }

    pub fn bounding_box(self: Hittable) AABB {
        return switch (self) {
            .primitive => |p| p.bounding_box(),
            .bvh_node => |b| b.bounding_box(),
        };
    }

    pub fn deinit(self: *Hittable, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .primitive => {}, // Nothing to free for a sphere
            .bvh_node => |b| b.deinit(allocator),
        }
        allocator.destroy(self);
    }

    pub fn create_from_bvh(allocator: std.mem.Allocator, node: *BVHNode) !*Hittable {
        const hittable = try allocator.create(Hittable);
        hittable.* = Hittable{ .bvh_node = node };
        return hittable;
    }
};
