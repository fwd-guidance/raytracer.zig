const std = @import("std");
const math = @import("math.zig");
const primitives = @import("primitives.zig");
const scene = @import("scene.zig");

const hit_record = scene.hit_record;
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
        //return AABB{
        //    .x = x,
        //    .y = y,
        //    .z = z,
        //};
    }

    pub fn empty() AABB {
        const empty_interval = Interval.empty();
        return AABB.init(empty_interval, empty_interval, empty_interval);
    }

    pub fn fromPoints(a: @Vector(3, f32), b: @Vector(3, f32)) AABB {
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
};

pub const BVHNode = struct {
    left: *Hittable,
    right: *Hittable,
    bbox: AABB,

    const Self = @This();

    // Construct a bounding volume hierarchy node from a range of hittables
    pub fn initFromList(allocator: std.mem.Allocator, objects: []Primitive) !*BVHNode {
        return try initFromSpan(allocator, objects, 0, objects.len);
    }

    pub fn initFromSpan(allocator: std.mem.Allocator, objects: []Primitive, start: usize, end: usize) !*BVHNode {
        var node = try allocator.create(BVHNode);

        var span_bbox = AABB.empty();
        for (start..end) |i| {
            span_bbox = AABB.merge(span_bbox, objects[i].boundingBox());
        }
        const axis = span_bbox.longest_axis();

        const object_span = end - start;

        if (object_span == 1) {
            node.left = try createHittableFromPrimitive(allocator, objects[start]);
            node.right = node.left;
        } else if (object_span == 2) {
            if (boxCompare(objects[start], objects[start + 1], axis)) {
                node.left = try createHittableFromPrimitive(allocator, objects[start]);
                node.right = try createHittableFromPrimitive(allocator, objects[start + 1]);
            } else {
                node.left = try createHittableFromPrimitive(allocator, objects[start + 1]);
                node.right = try createHittableFromPrimitive(allocator, objects[start]);
            }
        } else {
            sortPrimitivesByAxis(objects[start..end], axis);

            const mid = start + object_span / 2;

            node.left = try Hittable.createFromBVH(allocator, try initFromSpan(allocator, objects, start, mid));
            node.right = try Hittable.createFromBVH(allocator, try initFromSpan(allocator, objects, mid, end));
        }

        const box_left = getBoxForHittable(node.left);
        const box_right = getBoxForHittable(node.right);
        node.bbox = AABB.merge(box_left, box_right);
        return node;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.left.deinit(allocator);
        if (self.right != self.left) { // Avoid double-freeing if both point to same object
            self.right.deinit(allocator);
        }
        allocator.destroy(self);
    }

    pub fn hit(self: Self, r: Ray, ray_t: Interval, rec: *hit_record) bool {
        // If ray doesn't hit the bounding box, return false immediately
        if (!self.bbox.hit(r, ray_t)) {
            return false;
        }

        // Check hit with left child
        const hit_left = self.left.hit(r, ray_t, rec);

        // Check hit with right child, using a potentially narrower interval if left was hit
        const right_ray_t = if (hit_left)
            Interval.init(ray_t.min, rec.t)
        else
            ray_t;

        const hit_right = self.right.hit(r, right_ray_t, rec);

        return (hit_left or hit_right);
    }

    pub fn boundingBox(self: Self) AABB {
        return self.bbox;
    }
};

// Helper function to compare two spheres by a given axis
fn boxCompare(a: Primitive, b: Primitive, axis: u8) bool {
    const box_a = a.boundingBox();
    const box_b = b.boundingBox();

    switch (axis) {
        0 => return box_a.x.min < box_b.x.min, // x-axis
        1 => return box_a.y.min < box_b.y.min, // y-axis
        2 => return box_a.z.min < box_b.z.min, // z-axis
        else => @panic("Invalid axis"),
    }
}

// Helper function to sort spheres by a given axis
fn sortPrimitivesByAxis(objects: []Primitive, axis: u8) void {
    const Context = struct {
        axis: u8,
        pub fn lessThan(self: @This(), a: Primitive, b: Primitive) bool {
            return boxCompare(a, b, self.axis);
        }
    };

    std.sort.insertion(Primitive, objects, Context{ .axis = axis }, Context.lessThan);

    //std.sort.pdq(Sphere, objects, Context{ .axis = axis }, Context.lessThan);
}

// Helper function to get the bounding box for a sphere
fn getSphereBox(sphere: Sphere) AABB {
    return sphere.boundingBox();
}

// Helper to get the bounding box for a hittable
fn getBoxForHittable(hittable: *Hittable) AABB {
    return hittable.boundingBox();
}

// Helper to create a hittable from a sphere
fn createHittableFromPrimitive(allocator: std.mem.Allocator, primitive: Primitive) !*Hittable {
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

    pub fn hit(self: Hittable, r: Ray, ray_t: Interval, rec: *hit_record) bool {
        return switch (self) {
            .primitive => |p| p.hit(&r, ray_t, rec),
            .bvh_node => |b| b.hit(r, ray_t, rec),
        };
    }

    pub fn boundingBox(self: Hittable) AABB {
        return switch (self) {
            .primitive => |p| p.boundingBox(),
            .bvh_node => |b| b.boundingBox(),
        };
    }

    pub fn deinit(self: *Hittable, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .primitive => {}, // Nothing to free for a sphere
            .bvh_node => |b| b.deinit(allocator),
        }
        allocator.destroy(self);
    }

    pub fn createFromBVH(allocator: std.mem.Allocator, node: *BVHNode) !*Hittable {
        const hittable = try allocator.create(Hittable);
        hittable.* = Hittable{ .bvh_node = node };
        return hittable;
    }
};
