const rtw = @import("rtweekend.zig");

const hit_record = rtw.hittable.hit_record;
const vec = rtw.vec;
const init = rtw.vec.init;
const Ray = rtw.ray.Ray;
const std = rtw.std;
const Interval = rtw.interval.Interval;
const Material = rtw.Material;
const aabb = rtw.aabb;

pub const sphere = struct {
    center: @Vector(3, f64),
    radius: f64,
    mat: Material,
    is_moving: bool,
    center_vec: ?@Vector(3, f64),
    bbox: aabb,
    const Self = @This();

    pub fn bounding_box(self: Self) aabb {
        return self.bbox;
    }

    pub fn stationary_init(center: @Vector(3, f64), radius: f64, mat: Material) sphere {
        const rvec: @Vector(3, f64) = init(radius, radius, radius);
        const bbox: aabb = aabb.vec_init(center - rvec, center + rvec);
        return sphere{ .center = center, .radius = radius, .mat = mat, .is_moving = false, .center_vec = null, .bbox = bbox };
    }

    pub fn moving_init(center1: @Vector(3, f64), center2: @Vector(3, f64), radius: f64, mat: Material) sphere {
        const rvec: @Vector(3, f64) = init(radius, radius, radius);
        const box1: aabb = aabb.vec_init(center1 - rvec, center1 + rvec);
        const box2: aabb = aabb.vec_init(center2 - rvec, center2 + rvec);
        const bbox: aabb = aabb.aabb_init(box1, box2);
        const center_vec: @Vector(3, f64) = center2 - center1;
        return sphere{ .center = center1, .radius = radius, .mat = mat, .is_moving = true, .center_vec = center_vec, .bbox = bbox };
    }

    pub fn set_center_vector(center1: @Vector(3, f64), center2: @Vector(3, f64)) @Vector(3, f64) {
        return center2 - center1;
    }

    pub fn sphere_center(self: Self, time: f64) !@Vector(3, f64) {
        return self.center + try rtw.vec.scale(self.center_vec.?, time);
    }

    pub fn hit(self: Self, r: *const Ray, ray_t: Interval, rec: *hit_record) bool {
        const center: @Vector(3, f64) = if (self.is_moving) try sphere_center(self, r.*.tm) else self.center;
        const oc: @Vector(3, f64) = center - r.*.origin;
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
        const outward_normal: @Vector(3, f64) = (rec.*.p - self.center) / init(self.radius, self.radius, self.radius);
        rec.set_face_normal(r, &outward_normal);
        rec.*.mat = self.mat;

        return true;
    }
};
