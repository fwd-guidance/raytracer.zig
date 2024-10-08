const rtw = @import("rtweekend.zig");

const Ray = rtw.ray.Ray;
const vec = rtw.vec;
const Material = rtw.Material;

pub const hit_record = struct {
    p: @Vector(3, f64),
    t: f64,
    mat: Material,
    normal: @Vector(3, f64),
    front_face: bool,
    const Self = @This();

    pub fn set_face_normal(self: *Self, r: *const Ray, outward_normal: *const @Vector(3, f64)) void {
        // Sets the hit record normal Vector
        // NOTE: the parameter outward_normal is assumed to have unit length

        self.*.front_face = (try vec.dot(r.direction, outward_normal.*)) < 0;
        self.*.normal = if (self.*.front_face) outward_normal.* else try vec.invert(outward_normal.*);
    }
};
