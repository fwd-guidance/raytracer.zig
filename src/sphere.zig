const hittable = @import("hittable.zig");
const vec = @import("vec.zig");
const ray = @import("ray.zig");
const std = @import("std");
const interval = @import("interval.zig");
const Interval = interval.Interval;

pub const sphere = struct {
    center: @Vector(3, f64),
    radius: f64,
    const Self = @This();

    pub fn hit(self: Self, r: *ray.Ray, ray_t: Interval, rec: *hittable.hit_record) bool {
        const oc: @Vector(3, f64) = self.center - r.*.origin;
        const a: f64 = try vec.square_magnitude(r.*.direction);
        const h: f64 = try vec.dot(r.*.direction, oc);
        const c: f64 = try vec.square_magnitude(oc) - self.radius * self.radius;

        const discriminant: f64 = h * h - a * c;
        if (discriminant < 0) return false;

        //const sqrtd: f64 = std.math.sqrt(discriminant);

        // Find the nearest root that lies in the acceptable range
        var root: f64 = (h - std.math.sqrt(discriminant)) / a;
        if (!ray_t.surrounds(root)) {
            root = (h + std.math.sqrt(discriminant)) / a;
            if (!ray_t.surrounds(root)) {
                return false;
            }
        }

        rec.*.t = root;

        rec.*.p = try r.position(root);
        const outward_normal: @Vector(3, f64) = (rec.*.p - self.center) / vec.init(self.radius, self.radius, self.radius);
        rec.set_face_normal(r, @constCast(&outward_normal));

        return true;
    }
};
