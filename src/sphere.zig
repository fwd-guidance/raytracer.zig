const rtw = @import("rtweekend.zig");

const hit_record = rtw.hittable.hit_record;
const vec = rtw.vec;
const init = rtw.vec.init;
const Ray = rtw.ray.Ray;
const std = rtw.std;
const Interval = rtw.interval.Interval;
const Material = rtw.Material;
const AABB = @import("aabb.zig").AABB;
const Vec3 = @import("vec.zig").Vec3;
const Point3 = @import("vec.zig").Point3;

pub const sphere = struct {
    center: @Vector(3, f32),
    radius: f32,
    mat: Material,
    bbox: AABB, // Cached bounding box

    const Self = @This();

    pub fn init(center: @Vector(3, f32), radius: f32, mat: Material) Self {
        // Create the sphere and its bounding box
        const radius_vec = @Vector(3, f32){ radius, radius, radius };
        const min_point = center - radius_vec;
        const max_point = center + radius_vec;

        const x_interval = Interval.init(min_point[0], max_point[0]);
        const y_interval = Interval.init(min_point[1], max_point[1]);
        const z_interval = Interval.init(min_point[2], max_point[2]);

        return Self{
            .center = center,
            .radius = radius,
            .mat = mat,
            .bbox = AABB.init(x_interval, y_interval, z_interval),
        };
    }

    pub fn hit(self: Self, r: *const Ray, ray_t: Interval, rec: *hit_record) bool {
        // First test if ray hits the bounding box
        if (!self.bbox.hit(r.*, ray_t)) {
            return false;
        }

        const oc: @Vector(3, f32) = self.center - r.*.origin;
        const a: f32 = try vec.square_magnitude(r.*.direction);
        const h: f32 = try vec.dot(r.*.direction, oc);
        const c: f32 = try vec.square_magnitude(oc) - self.radius * self.radius;

        const discriminant: f32 = h * h - a * c;
        if (discriminant < 0) return false;

        // Find the nearest root that lies in the acceptable range
        var root: f32 = (h - std.math.sqrt(discriminant)) / a;
        if (!ray_t.surrounds(root)) {
            root = (h + std.math.sqrt(discriminant)) / a;
            if (!ray_t.surrounds(root)) {
                return false;
            }
        }

        rec.*.t = root;

        rec.*.p = try r.position(root);
        const outward_normal: @Vector(3, f32) = (rec.*.p - self.center) / @import("vec.zig").init(self.radius, self.radius, self.radius);
        rec.set_face_normal(r, &outward_normal);
        rec.*.mat = self.mat;

        return true;
    }

    pub fn boundingBox(self: Self) AABB {
        return self.bbox;
    }
};
