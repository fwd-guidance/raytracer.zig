const rtw = @import("rtweekend.zig");

const vec = rtw.vec;

pub const Ray = struct {
    origin: @Vector(3, f64),
    direction: @Vector(3, f64),
    tm: f64,

    pub fn init(origin: @Vector(3, f64), direction: @Vector(3, f64), tm: ?f64) Ray {
        return Ray{ .origin = origin, .direction = direction, .tm = tm orelse 0 };
    }

    pub fn position(self: Ray, t: f64) !@Vector(3, f64) {
        return self.origin + try vec.scale(self.direction, t);
    }
};
