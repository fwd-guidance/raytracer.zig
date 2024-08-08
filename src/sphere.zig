const hittable = @import("hittable.zig");
const vec = @import("vec.zig");
const ray = @import("ray.zig");
const std = @import("std");

pub const sphere = struct {
    center: @Vector(3, f64),
    radius: f64,
    const Self = @This();

    pub fn hit(self: Self, r: *ray.Ray, ray_tMin: f64, ray_tMax: f64, rec: *hittable.hit_record) bool {
        const oc: @Vector(3, f64) = self.center - r.*.origin;
        const a: f64 = try vec.square_magnitude(r.*.direction);
        const h: f64 = try vec.dot(r.*.direction, oc);
        const c: f64 = try vec.square_magnitude(oc) - self.radius * self.radius;

        //std.debug.print("NEW oc = {},    a = {},       h = {},       c = {}\n", .{ oc, a, h, c });

        const discriminant: f64 = h * h - a * c;
        //std.debug.print("NEW DISCRIMINANT = {}\n", .{discriminant});
        if (discriminant < 0) return false;

        //const sqrtd: f64 = std.math.sqrt(discriminant);

        // Find the nearest root that lies in the acceptable range
        var root: f64 = (h - std.math.sqrt(discriminant)) / a;
        //std.debug.print("NEW ROOT 1 = {}\n", .{root});
        if (root <= ray_tMin or ray_tMax <= root) {
            root = (h + std.math.sqrt(discriminant)) / a;
            if (root <= ray_tMin or ray_tMax <= root) {
                return false;
            }
        }
        //std.debug.print("NEW ROOT = {}\n", .{root});

        rec.*.t = root;
        //std.debug.print("rec.*.t = {}\n", .{rec.*.t});

        rec.*.p = try r.position(root);
        //std.debug.print("rec.*.p = {}\n", .{rec.*.p});
        const outward_normal: @Vector(3, f64) = (rec.*.p - self.center) / vec.init(self.radius, self.radius, self.radius);
        //std.debug.print("NEW = {}\n", .{outward_normal});
        rec.set_face_normal(r, @constCast(&outward_normal));
        //std.debug.print("NEW + {}\n", .{rec.*.normal});

        return true;
    }
};
