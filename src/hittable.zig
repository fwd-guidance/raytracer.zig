const rtw = @import("rtweekend.zig");

const Ray = rtw.ray.Ray;
const vec = rtw.vec;

pub const hit_record = struct {
    p: @Vector(3, f32),
    t: f32,
    mat_id: usize,
    normal: @Vector(3, f32),
    front_face: bool,
    const Self = @This();

    pub fn set_face_normal(self: *Self, r: *const Ray, outward_normal: *const @Vector(3, f32)) void {
        // Sets the hit record normal Vector
        // NOTE: the parameter outward_normal is assumed to have unit length

        self.*.front_face = (vec.dot(r.direction, outward_normal.*)) < 0;
        self.*.normal = if (self.*.front_face) outward_normal.* else vec.invert(outward_normal.*);
    }
};
