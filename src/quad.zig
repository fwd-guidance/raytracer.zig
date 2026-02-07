const rtw = @import("rtweekend.zig");
const vec = rtw.vec;
const Ray = rtw.Ray;
const Interval = rtw.Interval;
const hit_record = rtw.hit_record;
const AABB = @import("aabb.zig").AABB;

pub const Quad = struct {
    Q: @Vector(3, f32),
    u: @Vector(3, f32),
    v: @Vector(3, f32),
    w: @Vector(3, f32),
    normal: @Vector(3, f32),
    D: f32,
    mat_id: usize,
    bbox: AABB,

    pub fn init(Q: @Vector(3, f32), u: @Vector(3, f32), v: @Vector(3, f32), mat_id: usize) Quad {
        const n = vec.cross(u, v);
        const normal = vec.unit(n);

        return .{
            .Q = Q,
            .u = u,
            .v = v,
            .w = n / @as(@Vector(3, f32), @splat(vec.dot(n, n))),
            .normal = normal,
            .D = vec.dot(normal, Q),
            .mat_id = mat_id,
            .bbox = set_bounding_box(Q, u, v),
        };
    }

    pub fn set_bounding_box(Q: @Vector(3, f32), u: @Vector(3, f32), v: @Vector(3, f32)) AABB {
        const bbox_diagonal1 = AABB.fromPoints(Q, Q + u + v);
        const bbox_diagonal2 = AABB.fromPoints(Q + u, Q + v);
        return AABB.merge(bbox_diagonal1, bbox_diagonal2);
    }

    pub fn bounding_box(self: Quad) AABB {
        return self.bbox;
    }

    pub fn hit(self: Quad, r: *const Ray, ray_t: Interval, rec: *hit_record) bool {
        const denom = vec.dot(self.normal, r.*.direction);
        // bounds check unnecessary?
        if (@abs(denom) < 1e-8) return false;

        const t = (self.D - vec.dot(self.normal, r.*.origin)) / denom;
        if (!ray_t.contains(t)) return false;

        const intersection = r.*.position(t);

        const planar_hitpoint_vec = intersection - self.Q;
        const alpha = vec.dot(self.w, vec.cross(planar_hitpoint_vec, self.v));
        const beta = vec.dot(self.w, vec.cross(self.u, planar_hitpoint_vec));

        if (!is_interior(alpha, beta, rec)) return false;

        rec.*.t = t;
        rec.*.p = intersection;
        rec.*.mat_id = self.mat_id;
        rec.*.set_face_normal(r, &self.normal);
        return true;
    }

    pub fn is_interior(a: f32, b: f32, rec: *hit_record) bool {
        const unit_interval = Interval.init(0, 1);

        if (!unit_interval.contains(a) or !unit_interval.contains(b)) return false;

        rec.*.u = a;
        rec.*.v = b;

        return true;
    }
};
