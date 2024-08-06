const hittable = @import("hittable.zig");
const vec = @import("vec.zig");
const ray = @import("ray.zig");

const sphere = struct {
    center: @Vector(3, f64),
    radius: f64,

    pub fn hit(self: sphere, r: ray.Ray, ray_tMin: f64, ray_tMax: f64, rec: hittable.hit_record) bool {
        const oc: @Vector(3, f64) = self.center - r.origin;
        const a: f64 = try vec.square_magnitude(r.direction);
        const h: f64 = try vec.dot(r.direction, oc);
        const c: f64 = try vec.square_magnitude(oc) - self.radius * self.radius;

        const discriminant: f64 = h * h - a * c;
        if (discriminant < 0) return false;

        const sqrtd: f64 = @sqrt(discriminant);

        // Find the nearest root that lies in the acceptable range
        var root: f64 = (h - sqrtd) / a;
        if (root <= ray_tMin or ray_tMax <= root) {
            root = (h + sqrtd) / a;
            if (root <= ray_tMin or ray_tMax <= root) {
                return false;
            }
        }

        rec.t = root;
        rec.p = r.at(rec.t);
        const outward_normal: @Vector(3, f64) = (rec.p - self.center) / vec.init(self.radius, self.radius, self.radius);
        rec.set_face_normal(r, outward_normal);

        return true;
    }
};
