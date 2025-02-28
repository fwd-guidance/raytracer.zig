const rtw = @import("rtweekend.zig");
const Interval = rtw.interval.Interval;

pub const aabb = struct {
    x: Interval,
    y: Interval,
    z: Interval,
    const Self = @This();

    pub fn empty_aabb() aabb {
        return aabb{ .x = null, .y = null, .z = null };
    }

    pub fn interval_init(x: Interval, y: Interval, z: Interval) aabb {
        return aabb{ .x = x, .y = y, .z = z };
    }

    pub fn vec_init(a: @Vector(3, f64), b: @Vector(3, f64)) aabb {
        return aabb{
            .x = if (a[0] <= b[0]) Interval{ .min = a[0], .max = b[0] } else Interval{ .min = b[0], .max = a[0] },
            .y = if (a[1] <= b[1]) Interval{ .min = a[1], .max = b[1] } else Interval{ .min = b[1], .max = a[1] },
            .z = if (a[2] <= b[2]) Interval{ .min = a[2], .max = b[2] } else Interval{ .min = b[2], .max = a[2] },
        };
    }

    pub fn aabb_init(box0: ?aabb, box1: aabb) aabb {
        return aabb{ .x = Interval.init(box0.x, box1.x), .y = Interval.init(box0.y, box1.y), .z = Interval.init(box0.z, box1.z) };
    }

    pub fn axis_interval(self: Self, n: i8) !Interval {
        if (n == 1) return self.y;
        if (n == 2) return self.z;
        return self.x;
    }

    pub fn hit(self: Self, r: *const rtw.Ray, ray_t: Interval) !bool {
        const ray_orig: @Vector(3, f64) = r.*.origin;
        const ray_dir: @Vector(3, f64) = r.*.direction;

        var axis: i8 = 0;
        while (axis < 3) : (axis += 1) {
            const ax: *const Interval = try axis_interval(self, axis);
            const adinv: f64 = 1.0 / ray_dir[axis];

            const t0: f64 = (ax.min - ray_orig[axis]) * adinv;
            const t1: f64 = (ax.max - ray_orig[axis]) * adinv;

            if (t0 < t1) {
                if (t0 > ray_t.min) ray_t.min = t0;
                if (t1 < ray_t.max) ray_t.max = t1;
            } else {
                if (t1 > ray_t.min) ray_t.min = t1;
                if (t0 < ray_t.max) ray_t.max = t0;
            }

            if (ray_t.max <= ray_t.min) return false;
        }
        return true;
    }
};
