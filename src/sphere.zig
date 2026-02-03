const rtw = @import("rtweekend.zig");

const hit_record = rtw.hittable.hit_record;
const vec = rtw.vec;
const init = rtw.vec.init;
const Ray = rtw.ray.Ray;
const std = rtw.std;
const Interval = rtw.interval.Interval;
const Material = rtw.Material;
const AABB = @import("aabb.zig").AABB;

pub const sphere = struct {
    center: @Vector(3, f32),
    radius: f32,
    inv_radius: f32,
    radius_squared: f32,
    mat_id: usize,

    const Self = @This();

    pub fn init(center: @Vector(3, f32), radius: f32, mat_id: usize) Self {
        return Self{
            .center = center,
            .radius = radius,
            .inv_radius = 1.0 / radius,
            .radius_squared = radius * radius,
            .mat_id = mat_id,
        };
    }
    pub fn hit(self: Self, r: *const Ray, ray_t: Interval, rec: *hit_record) bool {
        // NOTE: a little sus of this "optimization" of hoisting field accesses. feels like something the compiler would handle itself
        const ray_origin = r.origin;
        const ray_dir = r.direction;

        //const oc: @Vector(3, f32) = self.center - r.*.origin;
        const oc: @Vector(3, f32) = self.center - ray_origin;
        //const a: f32 = vec.square_magnitude(r.*.direction);
        const a: f32 = vec.square_magnitude(ray_dir);
        //const h: f32 = vec.dot(r.*.direction, oc);
        const h: f32 = vec.dot(ray_dir, oc);
        const c: f32 = vec.square_magnitude(oc) - self.radius_squared;

        const discriminant: f32 = h * h - a * c;
        if (discriminant < 0) return false;

        const sqrt_discriminant = @sqrt(discriminant);
        const inv_a = 1.0 / a;

        // Find the nearest root that lies in the acceptable range
        var root: f32 = (h - sqrt_discriminant) * inv_a;
        if (!ray_t.surrounds(root)) {
            root = (h + sqrt_discriminant) * inv_a;
            if (!ray_t.surrounds(root)) {
                return false;
            }
        }

        rec.*.t = root;

        rec.*.p = r.position(root);
        const outward_normal: @Vector(3, f32) = (rec.*.p - self.center) * @as(@Vector(3, f32), @splat(self.inv_radius));
        rec.set_face_normal(r, &outward_normal);
        rec.*.mat_id = self.mat_id;

        return true;
    }

    pub fn boundingBox(self: Self) AABB {
        const r_vec = @Vector(3, f32){ self.radius, self.radius, self.radius };
        return AABB.fromPoints(self.center - r_vec, self.center + r_vec);
    }
};
