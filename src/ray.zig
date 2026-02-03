const rtw = @import("rtweekend.zig");

const vec = rtw.vec;

pub const Ray = struct {
    origin: @Vector(3, f32),
    direction: @Vector(3, f32),
    inv_direction: @Vector(3, f32),
    tm: f32,

    pub fn init(origin: @Vector(3, f32), direction: @Vector(3, f32), tm: ?f32) Ray {
        return .{ .origin = origin, .direction = direction, .inv_direction = compute_inv_direction(direction), .tm = tm orelse 0 };
    }

    inline fn compute_inv_direction(direction: @Vector(3, f32)) @Vector(3, f32) {
        return @Vector(3, f32){
            if (direction[0] != 0.0) 1.0 / direction[0] else rtw.std.math.inf(f32),
            if (direction[1] != 0.0) 1.0 / direction[1] else rtw.std.math.inf(f32),
            if (direction[2] != 0.0) 1.0 / direction[2] else rtw.std.math.inf(f32),
        };
    }

    pub fn position(self: Ray, t: f32) @Vector(3, f32) {
        return self.origin + vec.scale(self.direction, t);
    }
};
