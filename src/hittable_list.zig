const rtw = @import("rtweekend.zig");

const Interval = rtw.interval.Interval;
const std = rtw.std;
const Ray = rtw.ray.Ray;
const hit_record = rtw.hittable.hit_record;
const Sphere = rtw.sphere.sphere;
const Material = rtw.material.Material;
const ArrayList = std.ArrayList;
const AABB = @import("aabb.zig").AABB;
const BVHNode = @import("bvh.zig").BVHNode;
const Hittable = @import("bvh.zig").Hittable;

pub const HittableList = struct {
    objects: ArrayList(Sphere),
    bvh_root: ?*Hittable, // Optional BVH root node
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ 
            .objects = ArrayList(Sphere).init(allocator),
            .bvh_root = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        // Free BVH if it exists
        if (self.bvh_root != null) {
            self.bvh_root.?.deinit(self.allocator);
            self.bvh_root = null;
        }
        
        self.*.objects.deinit();
    }

    pub fn add(self: *Self, _sphere: Sphere) anyerror!*Self {
        try self.*.objects.append(_sphere);
        // Clear BVH since we've modified the object list
        if (self.bvh_root != null) {
            self.bvh_root.?.deinit(self.allocator);
            self.bvh_root = null;
        }
        return self;
    }
    
    // Build the BVH from the current list of objects
    pub fn buildBVH(self: *Self) !void {
        // Clear the existing BVH if it exists
        if (self.bvh_root != null) {
            self.bvh_root.?.deinit(self.allocator);
            self.bvh_root = null;
        }
        
        // Only build if we have objects
        if (self.objects.items.len > 0) {
            // Create the BVH root node from all spheres
            const bvh_node = try BVHNode.initFromList(self.allocator, self.objects.items);
            self.bvh_root = try Hittable.createFromBVH(self.allocator, bvh_node);
        }
    }

    pub fn hit(self: Self, r: Ray, ray_t: Interval, rec: *hit_record) bool {
        // If BVH is built, use it for faster intersection testing
        if (self.bvh_root != null) {
            return self.bvh_root.?.hit(r, ray_t, rec);
        }
        
        // Fall back to linear traversal if no BVH
        var temp_rec: hit_record = undefined;
        var hit_anything: bool = false;
        var closest_so_far = ray_t.max;

        for (self.objects.items) |object| {
            if (object.hit(&r, Interval.init(ray_t.min, closest_so_far), @constCast(&temp_rec))) {
                hit_anything = true;
                closest_so_far = temp_rec.t;
                rec.* = temp_rec;
            }
        }
        return hit_anything;
    }
    
    pub fn boundingBox(self: Self) AABB {
        if (self.objects.items.len == 0) {
            return AABB.empty();
        }
        
        // If BVH exists, use its bounding box
        if (self.bvh_root != null) {
            return self.bvh_root.?.boundingBox();
        }
        
        // Otherwise compute it from scratch
        var result = self.objects.items[0].boundingBox();
        
        for (self.objects.items[1..]) |object| {
            result = AABB.merge(result, object.boundingBox());
        }
        
        return result;
    }
};
