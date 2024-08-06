const vec = @import("vec.zig");

pub const Ray = struct {
    origin: @Vector(3, f64),
    direction: @Vector(3, f64),

    pub fn init(origin: @Vector(3, f64), direction: @Vector(3, f64)) Ray {
        return Ray{ .origin = origin, .direction = direction };
    }

    pub fn position(self: Ray, t: f64) !@Vector(3, f64) {
        return self.origin + vec.scale(self.direction, t);
    }
};
