const rtw = @import("rtweekend.zig");

const vec = rtw.vec;

pub const Ray = struct {
    origin: @Vector(3, f32),
    direction: @Vector(3, f32),
    tm: f32,

    pub fn init(origin: @Vector(3, f32), direction: @Vector(3, f32), tm: ?f32) Ray {
        return Ray{ .origin = origin, .direction = direction, .tm = tm orelse 0 };
    }

    pub fn position(self: Ray, t: f32) !@Vector(3, f32) {
        return self.origin + try vec.scale(self.direction, t);
    }
};
