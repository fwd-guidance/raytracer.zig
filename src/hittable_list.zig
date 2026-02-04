const rtw = @import("rtweekend.zig");

const Interval = rtw.interval.Interval;
const std = rtw.std;
const Ray = rtw.ray.Ray;
const hit_record = rtw.hittable.hit_record;
const Sphere = rtw.sphere.Sphere;
const Material = rtw.material.Material;
const ArrayList = std.ArrayList;
const MultiArrayList = std.MultiArrayList;
const AABB = @import("aabb.zig").AABB;
const BVHNode = @import("bvh.zig").BVHNode;
const Hittable = @import("bvh.zig").Hittable;
const vec = @import("vec.zig");

pub const HittableList = struct {
    objects: MultiArrayList(Sphere),
    materials: ArrayList(Material),
    bvh_root: ?*Hittable, // Optional BVH root node
    bbox: AABB,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .objects = MultiArrayList(Sphere){},
            .materials = ArrayList(Material){},
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

        self.*.objects.deinit(self.allocator);
        self.materials.deinit(self.allocator);
    }

    pub fn add_material(self: *Self, mat: Material) !usize {
        try self.materials.append(self.allocator, mat);
        return self.materials.items.len - 1;
    }

    pub fn add(self: *Self, _sphere: Sphere) anyerror!*Self {
        try self.*.objects.append(self.allocator, _sphere);

        self.bbox = AABB.merge(self.bbox, _sphere.boundingBox());

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
        //if (self.objects.items.len > 0) {
        if (self.objects.len > 0) {

            //
            var tmp_spheres = try self.allocator.alloc(Sphere, self.objects.len);
            defer self.allocator.free(tmp_spheres);

            for (0..self.objects.len) |i| {
                tmp_spheres[i] = self.objects.get(i);
            }
            //
            // Create the BVH root node from all spheres
            //const bvh_node = try BVHNode.initfromlist(self.allocator, self.objects.items);

            const bvh_node = try BVHNode.initFromList(self.allocator, tmp_spheres);
            self.bvh_root = try Hittable.createFromBVH(self.allocator, bvh_node);
        }
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
        const centers = self.objects.items(.center);
        const radii = self.objects.items(.radius);
        const inv_radii = self.objects.items(.inv_radius);
        const mat_ids = self.objects.items(.mat_id);

        // 2. Iterate by index
        for (0..self.objects.len) |i| {
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
};
