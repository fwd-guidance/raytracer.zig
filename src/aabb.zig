const rtw = @import("rtweekend.zig");
const Interval = rtw.interval.Interval;

pub const aabb = struct {
    x: Interval,
    y: Interval,
    z: Interval,
    const Self = @This();

    pub fn init(x: Interval, y: Interval, z: Interval) aabb {
        return aabb{ .x = x, .y = y, .z = z };
    }

    pub fn alt_init(a: @Vector(3, f64), b: @Vector(3, f64)) aabb {
        return aabb{
            .x = if (a[0] <= b[0]) Interval{ a[0], b[0] } else Interval{ b[0], a[0] },
            .y = if (a[1] <= b[1]) Interval{ a[1], b[1] } else Interval{ b[1], a[1] },
            .z = if (a[2] <= b[2]) Interval{ a[2], b[2] } else Interval{ b[2], a[2] },
        };
    }

    pub fn aabb_init(box0: *const aabb, box1: *const aabb) aabb {
        return aabb{ .x = Interval{ box0.x, box1.x }, .y = Interval{ box0.y, box1.y }, .z = Interval{ box0.z, box1.z } };
    }

    pub fn axis_interval(self: Self, n: i8) !*Interval {
        if (n == 1) return &self.y;
        if (n == 2) return &self.z;
        return &self.x;
    }

    pub fn hit(self: Self, r: *const rtw.Ray, ray_t: Interval) !bool {
        const ray_orig: @Vector(3, f64) = r.*.origin;
        const ray_dir: @Vector(3, f64) = r.*.direction;

        var axis: i8 = 0;
        while (axis < 3) : (axis += 1) {
            const ax: *const Interval = axis_interval(self, axis);
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
