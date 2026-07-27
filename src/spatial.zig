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
    min: @Vector(3, f32),
    max: @Vector(3, f32),

    pub fn empty() AABB {
        const inf = math.vec3s(std.math.inf(f32));
        return .{ .min = inf, .max = -inf };
    }

    pub fn init_from_points(a: @Vector(3, f32), b: @Vector(3, f32)) AABB {
        return pad(.{ .min = @min(a, b), .max = @max(a, b) });
    }

    pub fn add(self: AABB, offset: @Vector(3, f32)) AABB {
        return .{ .min = self.min + offset, .max = self.max + offset };
    }

    pub fn merge(a: AABB, b: AABB) AABB {
        return .{ .min = @min(a.min, b.min), .max = @max(a.max, b.max) };
    }

    /// Widen any axis thinner than `delta` so flat primitives (a single
    /// z-plane Quad, e.g.) still get a non-degenerate box.
    pub fn pad(self: AABB) AABB {
        const delta = math.vec3s(0.0001);
        const half = math.vec3s(0.00005);
        const size = self.max - self.min;
        const needs_pad = size < delta;
        return .{
            .min = @select(f32, needs_pad, self.min - half, self.min),
            .max = @select(f32, needs_pad, self.max + half, self.max),
        };
    }

    pub fn longest_axis(self: AABB) u8 {
        const size = self.max - self.min;
        if (size[0] > size[1]) {
            return if (size[0] > size[2]) 0 else 2;
        } else {
            return if (size[1] > size[2]) 1 else 2;
        }
    }

    pub fn centroid(self: AABB) @Vector(3, f32) {
        return (self.min + self.max) * math.vec3s(0.5);
    }

    /// Half of the actual surface area -- the factor of 2 cancels out of the
    /// SAH cost comparison below, so we skip it entirely.
    pub fn half_surface_area(self: AABB) f32 {
        const d = self.max - self.min;
        return d[0] * d[1] + d[1] * d[2] + d[2] * d[0];
    }

    /// Slab test returning the entry distance, or null on miss. Takes t as two
    /// scalars instead of an Interval: in BVH traversal the t_max shrinks as we
    /// find hits, and threading a register through beats rebuilding an Interval
    /// struct (and the optional unwrap) at every node.
    pub fn hit_distance(self: *const AABB, r: *const Ray, t_min: f32, t_max: f32) ?f32 {
        const t0 = (self.min - r.origin) * r.inv_direction;
        const t1 = (self.max - r.origin) * r.inv_direction;

        const t_smaller = @min(t0, t1);
        const t_bigger = @max(t0, t1);

        const t_enter = @max(t_min, @reduce(.Max, t_smaller));
        const t_exit = @min(t_max, @reduce(.Min, t_bigger));

        if (t_enter <= t_exit) {
            return t_enter;
        } else {
            return null;
        }
    }
};

// ---------------------------------------------------------------------------
// Binned SAH split selection.
//
// Replaces "sort by longest axis, split at the middle index" with an actual
// cost estimate: for each of the 3 axes, bucket primitive centroids into
// SAH_BINS bins, sweep prefix/suffix surface areas, and pick whichever
// (axis, boundary) pair minimizes expected traversal cost. Falls back to the
// old median-split behavior if no split beats the cost of a bigger leaf
// (e.g. all centroids coincided on every axis).
//
// Leaves are still forced down to a single primitive (unchanged from before)
// -- this only changes *where* the tree splits, not the leaf size. A further
// step (allowing multi-primitive leaves) would need a new Hittable variant
// and is a bigger change; ask if you want that sketched too.
// ---------------------------------------------------------------------------
const SAH_BINS = 16;
const TRAVERSAL_COST: f32 = 1.0;
const INTERSECT_COST: f32 = 1.0;

/// @Vector(3, f32) can only be indexed with a comptime-known index -- `v[axis]`
/// doesn't compile when `axis` is a runtime u8. This switches on the runtime
/// value into three branches, each of which indexes with a literal (0/1/2),
/// which *is* comptime-known within each branch.
inline fn vecAt(v: @Vector(3, f32), axis: anytype) f32 {
    return switch (axis) {
        0 => v[0],
        1 => v[1],
        2 => v[2],
        else => unreachable,
    };
}

const SahBin = struct {
    bbox: AABB = AABB.empty(),
    count: usize = 0,
};

const SahSplit = struct {
    axis: u8,
    boundary: f32,
    cost: f32,
};

fn best_sah_split(objects: []const Primitive, centroid_bounds: AABB, parent_area: f32) ?SahSplit {
    var best: ?SahSplit = null;

    for (0..3) |axis| {
        const axis_min = vecAt(centroid_bounds.min, axis);
        const axis_max = vecAt(centroid_bounds.max, axis);
        const extent = axis_max - axis_min;
        if (extent < 1e-6) continue; // all centroids coincide on this axis

        var bins: [SAH_BINS]SahBin = @splat(SahBin{});
        const bins_per_extent = @as(f32, SAH_BINS) / extent;

        for (objects) |*obj| {
            const bbox = obj.bounding_box().*;
            const c = vecAt(bbox.centroid(), axis);
            var idx: usize = @intFromFloat(bins_per_extent * (c - axis_min));
            if (idx >= SAH_BINS) idx = SAH_BINS - 1;
            bins[idx].bbox = AABB.merge(bins[idx].bbox, bbox);
            bins[idx].count += 1;
        }

        // Prefix sweep: area/count of bins [0..b] merged together.
        var left_area: [SAH_BINS]f32 = undefined;
        var left_count: [SAH_BINS]usize = undefined;
        {
            var acc_box = AABB.empty();
            var acc_count: usize = 0;
            for (0..SAH_BINS) |b| {
                acc_box = AABB.merge(acc_box, bins[b].bbox);
                acc_count += bins[b].count;
                left_area[b] = acc_box.half_surface_area();
                left_count[b] = acc_count;
            }
        }

        // Suffix sweep: area/count of bins [b..SAH_BINS) merged together.
        var right_area: [SAH_BINS]f32 = undefined;
        var right_count: [SAH_BINS]usize = undefined;
        {
            var acc_box = AABB.empty();
            var acc_count: usize = 0;
            var b: usize = SAH_BINS;
            while (b > 0) {
                b -= 1;
                acc_box = AABB.merge(acc_box, bins[b].bbox);
                acc_count += bins[b].count;
                right_area[b] = acc_box.half_surface_area();
                right_count[b] = acc_count;
            }
        }

        for (0..SAH_BINS - 1) |boundary| {
            const nl = left_count[boundary];
            const nr = right_count[boundary + 1];
            if (nl == 0 or nr == 0) continue;

            const cost = TRAVERSAL_COST + INTERSECT_COST *
                (left_area[boundary] * @as(f32, @floatFromInt(nl)) +
                    right_area[boundary + 1] * @as(f32, @floatFromInt(nr))) / parent_area;

            if (best == null or cost < best.?.cost) {
                best = .{
                    .axis = @intCast(axis),
                    .boundary = axis_min + extent * @as(f32, @floatFromInt(boundary + 1)) / @as(f32, SAH_BINS),
                    .cost = cost,
                };
            }
        }
    }

    return best;
}

/// Partitions objects in-place into "centroid[axis] < boundary" (front) and
/// "centroid[axis] >= boundary" (back). Returns the split index.
fn partition_by_centroid(objects: []Primitive, axis: u8, boundary: f32) usize {
    var i: usize = 0;
    var j: usize = objects.len;
    while (i < j) {
        const c = vecAt(objects[i].bounding_box().centroid(), axis);
        if (c < boundary) {
            i += 1;
        } else {
            j -= 1;
            std.mem.swap(Primitive, &objects[i], &objects[j]);
        }
    }
    return i;
}

pub const BVHNode = struct {
    left: *Hittable,
    right: *Hittable,
    bbox: AABB,

    // Cached child bounding boxes: traversal reads these directly instead of
    // dispatching bounding_box() through the Hittable/Primitive unions twice
    // per node visit.
    left_bbox: AABB,
    right_bbox: AABB,

    pub fn init_from_list(allocator: std.mem.Allocator, objects: []Primitive) !*BVHNode {
        return try init_from_span(allocator, objects, 0, objects.len);
    }

    pub fn init_from_span(allocator: std.mem.Allocator, objects: []Primitive, start: usize, end: usize) !*BVHNode {
        var node = try allocator.create(BVHNode);
        const object_span = end - start;

        var span_bbox = AABB.empty();
        var centroid_bounds = AABB.empty();
        for (start..end) |i| {
            const bbox = objects[i].bounding_box().*;
            span_bbox = AABB.merge(span_bbox, bbox);
            const c = bbox.centroid();
            centroid_bounds = AABB.merge(centroid_bounds, .{ .min = c, .max = c });
        }

        if (object_span == 1) {
            node.left = try create_hittable_from_primitive(allocator, objects[start]);
            node.right = node.left;
        } else if (object_span == 2) {
            const axis = span_bbox.longest_axis();
            if (box_compare(objects[start], objects[start + 1], axis)) {
                node.left = try create_hittable_from_primitive(allocator, objects[start]);
                node.right = try create_hittable_from_primitive(allocator, objects[start + 1]);
            } else {
                node.left = try create_hittable_from_primitive(allocator, objects[start + 1]);
                node.right = try create_hittable_from_primitive(allocator, objects[start]);
            }
        } else {
            const parent_area = span_bbox.half_surface_area();
            const split = if (parent_area > 0) best_sah_split(objects[start..end], centroid_bounds, parent_area) else null;
            const leaf_cost = INTERSECT_COST * @as(f32, @floatFromInt(object_span));

            var mid: usize = undefined;
            if (split != null and split.?.cost < leaf_cost) {
                const local_mid = partition_by_centroid(objects[start..end], split.?.axis, split.?.boundary);
                mid = start + local_mid;
                // Degenerate partition (shouldn't happen given the bin check
                // above, but a hard safety net beats an infinite recursion).
                if (mid == start or mid == end) {
                    sort_primitives_by_axis(objects[start..end], span_bbox.longest_axis());
                    mid = start + object_span / 2;
                }
            } else {
                // SAH found nothing better than just splitting the span in
                // half (or all centroids coincided) -- fall back to the
                // original median-of-longest-axis behavior.
                sort_primitives_by_axis(objects[start..end], span_bbox.longest_axis());
                mid = start + object_span / 2;
            }

            node.left = try Hittable.create_from_bvh(allocator, try init_from_span(allocator, objects, start, mid));
            node.right = try Hittable.create_from_bvh(allocator, try init_from_span(allocator, objects, mid, end));
        }

        node.left_bbox = node.left.bounding_box().*;
        node.right_bbox = node.right.bounding_box().*;
        node.bbox = AABB.merge(node.left_bbox, node.right_bbox);
        return node;
    }

    pub fn deinit(self: *BVHNode, allocator: std.mem.Allocator) void {
        self.left.deinit(allocator);
        if (self.right != self.left) { // Avoid double-freeing if both point to same object
            self.right.deinit(allocator);
        }
        allocator.destroy(self);
    }

    pub fn hit(self: *const BVHNode, r: *const Ray, ray_t: Interval, rec: *HitRecord) bool {
        // True leaf (single primitive): left and right are the same pointer.
        // Test it once instead of twice.
        if (self.left == self.right) {
            return self.left.hit(r, ray_t, rec);
        }

        const closest = ray_t.max;

        const dist_left = self.left_bbox.hit_distance(r, ray_t.min, closest);
        const dist_right = self.right_bbox.hit_distance(r, ray_t.min, closest);

        // Traverse the closer child first so a hit there can prune the far child.
        if (dist_left != null and dist_right != null) {
            if (dist_left.? < dist_right.?) {
                const hit_l = self.left.hit(r, ray_t, rec);
                const t_max = if (hit_l) rec.t else ray_t.max;
                const right_interval = Interval.init(ray_t.min, t_max);
                const hit_r = self.right.hit(r, right_interval, rec);
                return hit_l or hit_r;
            } else {
                const hit_r = self.right.hit(r, ray_t, rec);
                const t_max = if (hit_r) rec.t else ray_t.max;
                const left_interval = Interval.init(ray_t.min, t_max);
                const hit_l = self.left.hit(r, left_interval, rec);
                return hit_r or hit_l;
            }
        } else if (dist_left != null) {
            return self.left.hit(r, ray_t, rec);
        } else if (dist_right != null) {
            return self.right.hit(r, ray_t, rec);
        } else {
            return false;
        }
    }

    pub fn bounding_box(self: *const BVHNode) *const AABB {
        return &self.bbox;
    }
};

// Helper function to compare two primitives by a given axis (centroid, not
// min -- comparing by min alone can imbalance splits when boxes vary a lot
// in size along the split axis). Only used for the span==2 case and the
// median-split fallback now; the main SAH path above ignores this.
fn box_compare(a: Primitive, b: Primitive, axis: u8) bool {
    const ca = vecAt(a.bounding_box().centroid(), axis);
    const cb = vecAt(b.bounding_box().centroid(), axis);
    return ca < cb;
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

    pub fn hit(self: *const Hittable, r: *const Ray, ray_t: Interval, rec: *HitRecord) bool {
        return switch (self.*) {
            .primitive => |*p| p.hit(r, ray_t, rec),
            .bvh_node => |b| b.hit(r, ray_t, rec),
        };
    }

    pub fn bounding_box(self: *const Hittable) *const AABB {
        return switch (self.*) {
            .primitive => |*p| p.bounding_box(),
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
