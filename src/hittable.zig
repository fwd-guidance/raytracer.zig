const ray = @import("ray.zig");
const vec = @import("vec.zig");

const hit_record = struct {
    p: @Vector(3, f64),
    t: f64,
    var normal: @Vector(3, f64) = undefined;
    var front_face: bool = undefined;

    pub fn set_face_normal(self: hit_record, r: ray.Ray, outward_normal: @Vector(3, f64)) bool {
        // Sets the hit record normal Vector
        // NOTE: the parameter outward_normal is assumed to have unit length

        self.front_face = (try vec.dot(r.direction, outward_normal)) < 0;
        self.normal = if (front_face) outward_normal else vec.invert(outward_normal);
    }
};
