const ray = @import("ray.zig");
const vec = @import("vec.zig");
const std = @import("std");

pub const hit_record = struct {
    p: @Vector(3, f64),
    t: f64,
    normal: @Vector(3, f64),
    front_face: bool,
    const Self = @This();

    pub fn set_face_normal(self: *Self, r: *ray.Ray, outward_normal: *@Vector(3, f64)) void {
        // Sets the hit record normal Vector
        // NOTE: the parameter outward_normal is assumed to have unit length

        self.*.front_face = (try vec.dot(r.direction, outward_normal.*)) < 0;
        self.*.normal = if (self.*.front_face) outward_normal.* else try vec.invert(outward_normal.*);
    }
};
