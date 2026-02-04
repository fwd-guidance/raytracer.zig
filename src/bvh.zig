const std = @import("std");
const rtw = @import("rtweekend.zig");
const Interval = @import("interval.zig").Interval;
const Ray = @import("ray.zig").Ray;
const hit_record = @import("hittable.zig").hit_record;
const AABB = @import("aabb.zig").AABB;
const Sphere = @import("sphere.zig").Sphere;
const vec = @import("vec.zig");

pub const BVHNode = struct {
    left: *Hittable,
    right: *Hittable,
    bbox: AABB,

    const Self = @This();

    // Construct a bounding volume hierarchy node from a range of hittables
    pub fn initFromList(allocator: std.mem.Allocator, objects: []Sphere) !*BVHNode {
        return try initFromSpan(allocator, objects, 0, objects.len);
    }

    pub fn initFromSpan(allocator: std.mem.Allocator, objects: []Sphere, start: usize, end: usize) !*BVHNode {
        var node = try allocator.create(BVHNode);
        //const axis = @as(u8, @intCast(rtw.random_int(0, 2)));

        var span_bbox = AABB.empty();
        for (start..end) |i| {
            span_bbox = AABB.merge(span_bbox, objects[i].boundingBox());
        }
        const axis = span_bbox.longest_axis();

        const object_span = end - start;

        if (object_span == 1) {
            node.left = try createHittableFromSphere(allocator, objects[start]);
            node.right = node.left;
        } else if (object_span == 2) {
            if (boxCompare(objects[start], objects[start + 1], axis)) {
                node.left = try createHittableFromSphere(allocator, objects[start]);
                node.right = try createHittableFromSphere(allocator, objects[start + 1]);
            } else {
                node.left = try createHittableFromSphere(allocator, objects[start + 1]);
                node.right = try createHittableFromSphere(allocator, objects[start]);
            }
        } else {
            // Sort the sub-slice in place — no copy needed.
            sortSpheresByAxis(objects[start..end], axis);

            const mid = start + object_span / 2;

            // Recurse on the now-sorted sub-slices.
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
fn boxCompare(a: Sphere, b: Sphere, axis: u8) bool {
    const box_a = getSphereBox(a);
    const box_b = getSphereBox(b);

    switch (axis) {
        0 => return box_a.x.min < box_b.x.min, // x-axis
        1 => return box_a.y.min < box_b.y.min, // y-axis
        2 => return box_a.z.min < box_b.z.min, // z-axis
        else => @panic("Invalid axis"),
    }
}

// Helper function to sort spheres by a given axis
fn sortSpheresByAxis(objects: []Sphere, axis: u8) void {
    const Context = struct {
        axis: u8,
        pub fn lessThan(self: @This(), a: Sphere, b: Sphere) bool {
            return boxCompare(a, b, self.axis);
        }
    };

    std.sort.insertion(Sphere, objects, Context{ .axis = axis }, Context.lessThan);

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
fn createHittableFromSphere(allocator: std.mem.Allocator, sphere: Sphere) !*Hittable {
    const hittable = try allocator.create(Hittable);
    hittable.* = Hittable{ .sphere = sphere };
    return hittable;
}

// A unified Hittable interface to handle different types
pub const HittableType = enum {
    sphere,
    bvh_node,
};

pub const Hittable = union(HittableType) {
    sphere: Sphere,
    bvh_node: *BVHNode,

    pub fn hit(self: Hittable, r: Ray, ray_t: Interval, rec: *hit_record) bool {
        return switch (self) {
            .sphere => |s| s.hit(&r, ray_t, rec),
            .bvh_node => |b| b.hit(r, ray_t, rec),
        };
    }

    pub fn boundingBox(self: Hittable) AABB {
        return switch (self) {
            .sphere => |s| getSphereBox(s),
            .bvh_node => |b| b.boundingBox(),
        };
    }

    pub fn deinit(self: *Hittable, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .sphere => {}, // Nothing to free for a sphere
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
