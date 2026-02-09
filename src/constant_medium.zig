const Primitive = @import("hittable_list.zig").Primitive;
const HittableList = @import("hittable_list.zig").HittableList;
const Ray = @import("ray.zig").Ray;
const Interval = @import("interval.zig").Interval;
const Material = @import("material.zig").Material;
const hit_record = @import("rtweekend.zig").hit_record;
const AABB = @import("aabb.zig").AABB;
const rtw = @import("rtweekend.zig");
const std = @import("std");
pub const ConstantMedium = struct {
    boundary: *Primitive,
    neg_inv_density: f32,
    phase_function_mat_id: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, boundary: Primitive, density: f32, tex_id: usize, world: *HittableList) !ConstantMedium {
        const boundary_ptr = try allocator.create(Primitive);
        boundary_ptr.* = boundary;

        // Create isotropic material and add to world
        const phase_function = Material.isotropic(tex_id);
        const mat_id = try world.add_material(phase_function);

        return .{
            .boundary = boundary_ptr,
            .neg_inv_density = -1.0 / density,
            .phase_function_mat_id = mat_id,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ConstantMedium) void {
        switch (self.boundary.*) {
            .Translate => |*t| t.deinit(),
            .RotateY => |*r| r.deinit(),
            .Box => |*b| b.deinit(),
            else => {},
        }
        self.allocator.destroy(self.boundary);
    }

    pub fn hit(self: ConstantMedium, r: *const Ray, ray_t: Interval, rec: *hit_record) bool {
        var rec1: hit_record = undefined;
        var rec2: hit_record = undefined;

        // Check if ray hits boundary at all
        if (!self.boundary.hit(r, Interval.universe(), &rec1)) {
            return false;
        }

        // Check if ray hits boundary again (exit point)
        if (!self.boundary.hit(r, Interval.init(rec1.t + 0.0001, std.math.inf(f32)), &rec2)) {
            return false;
        }

        // Clamp to valid ray interval
        if (rec1.t < ray_t.min) rec1.t = ray_t.min;
        if (rec2.t > ray_t.max) rec2.t = ray_t.max;

        if (rec1.t >= rec2.t) {
            return false;
        }

        if (rec1.t < 0) {
            rec1.t = 0;
        }

        const ray_length = rtw.vec.magnitude(r.direction);
        const distance_inside_boundary = (rec2.t - rec1.t) * ray_length;
        const hit_distance = self.neg_inv_density * @log(rtw.random_double());

        if (hit_distance > distance_inside_boundary) {
            return false;
        }

        rec.t = rec1.t + hit_distance / ray_length;
        rec.p = r.position(rec.t);

        rec.normal = @Vector(3, f32){ 1, 0, 0 }; // arbitrary
        rec.front_face = true; // also arbitrary
        rec.mat_id = self.phase_function_mat_id;

        return true;
    }

    pub fn bounding_box(self: ConstantMedium) AABB {
        return self.boundary.boundingBox();
    }
};
