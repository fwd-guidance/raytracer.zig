const Interval = @import("interval.zig").Interval;
const Ray = @import("ray.zig").Ray;

pub const AABB = struct {
    x: Interval,
    y: Interval,
    z: Interval,

    pub fn init(x: Interval, y: Interval, z: Interval) AABB {
        return AABB{
            .x = x,
            .y = y,
            .z = z,
        };
    }

    pub fn empty() AABB {
        const empty_interval = Interval.empty();
        return AABB.init(empty_interval, empty_interval, empty_interval);
    }

    pub fn fromPoints(a: @Vector(3, f32), b: @Vector(3, f32)) AABB {
        // The bounding box containing both points
        return AABB{
            .x = Interval.init(@min(a[0], b[0]), @max(a[0], b[0])),
            .y = Interval.init(@min(a[1], b[1]), @max(a[1], b[1])),
            .z = Interval.init(@min(a[2], b[2]), @max(a[2], b[2])),
        };
    }

    pub fn pad(self: AABB) AABB {
        // Return a new bounding box that is slightly larger than the original
        const delta = 0.0001;
        const new_x = if (self.x.size() >= delta) self.x else self.x.expand(delta);
        const new_y = if (self.y.size() >= delta) self.y else self.y.expand(delta);
        const new_z = if (self.z.size() >= delta) self.z else self.z.expand(delta);

        return AABB{
            .x = new_x,
            .y = new_y,
            .z = new_z,
        };
    }

    pub fn merge(a: AABB, b: AABB) AABB {
        return AABB{
            .x = Interval.merge(a.x, b.x),
            .y = Interval.merge(a.y, b.y),
            .z = Interval.merge(a.z, b.z),
        };
    }

    pub fn hit(self: AABB, r: Ray, ray_t: Interval) bool {
        // For each dimension, compute the times the ray enters and exits the box
        var t_min = ray_t.min;
        var t_max = ray_t.max;

        // Loop over the three dimensions for x=0, y=1, z=2
        inline for (0..3) |dim| {
            const invD = r.inv_direction[dim];
            const orig = r.origin[dim];
            const interval = switch (dim) {
                0 => self.x,
                1 => self.y,
                2 => self.z,
                else => unreachable,
            };

            // Calculate intersection with current axis
            var t0 = (interval.min - orig) * invD;
            var t1 = (interval.max - orig) * invD;

            // If ray is traveling in negative direction, swap t0 and t1
            if (invD < 0.0) {
                const temp = t0;
                t0 = t1;
                t1 = temp;
            }

            // Update overall intersection interval
            t_min = @max(t0, t_min);
            t_max = @min(t1, t_max);

            if (t_max <= t_min) {
                return false; // No intersection with this box
            }
        }

        return true; // Ray intersects box
    }
};
