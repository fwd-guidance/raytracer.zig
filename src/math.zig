const std = @import("std");
const utils = @import("utils.zig");

pub fn init(x: f32, y: f32, z: f32) @Vector(3, f32) {
    return .{ x, y, z };
}

pub fn random_vec() @Vector(3, f32) {
    return .{ utils.random_double(), utils.random_double(), utils.random_double() };
}

pub fn random_vec_range(min: f32, max: f32) @Vector(3, f32) {
    return .{ utils.random_double_range(min, max), utils.random_double_range(min, max), utils.random_double_range(min, max) };
}

pub fn add(v: @Vector(3, f32), scalar: f32) @Vector(3, f32) {
    return v + init(scalar, scalar, scalar);
}

pub fn scale(v: @Vector(3, f32), scalar: f32) @Vector(3, f32) {
    return v * init(scalar, scalar, scalar);
}

pub fn magnitude(v: @Vector(3, f32)) f32 {
    return @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
}

pub fn square_magnitude(v: @Vector(3, f32)) f32 {
    return v[0] * v[0] + v[1] * v[1] + v[2] * v[2];
}

pub fn near_zero(self: @Vector(3, f32)) bool {
    const s: f32 = 1e-8;
    return (@abs(self[0]) < s) and (@abs(self[1]) < s) and (@abs(self[2]) < s);
}

pub fn unit(v: @Vector(3, f32)) @Vector(3, f32) {
    const len = magnitude(v);
    return v / @as(@Vector(3, f32), @splat(len));
}

pub fn random_in_unit_disk() @Vector(3, f32) {
    while (true) {
        const p = @Vector(3, f32){ utils.random_double_range(-1, 1), utils.random_double_range(-1, 1), 0 };
        if (square_magnitude(p) < 1) return p;
    }
}

pub fn random_in_unit_sphere() @Vector(3, f32) {
    while (true) {
        const p = random_vec_range(-1, 1);
        if (square_magnitude(p) < 1) return p;
    }
}

pub fn random_unit_vector() @Vector(3, f32) {
    return unit(random_in_unit_sphere());
}

pub fn random_cosine_direction() @Vector(3, f32) {
    const r1 = utils.random_double();
    const r2 = utils.random_double();

    const phi = 2 * std.math.pi * r1;
    const x = @cos(phi) * @sqrt(r2);
    const y = @sin(phi) * @sqrt(r2);
    const z = @sqrt(1 - r2);

    return .{ x, y, z };
}

pub fn random_on_hemisphere(normal: @Vector(3, f32)) @Vector(3, f32) {
    const on_unit_sphere = random_unit_vector();
    if (dot(on_unit_sphere, normal) > 0.0) {
        return on_unit_sphere;
    } else {
        return -on_unit_sphere;
    }
}

pub fn reflect(v: *const @Vector(3, f32), n: *const @Vector(3, f32)) @Vector(3, f32) {
    return @constCast(v).* - scale(@constCast(n).*, dot(@constCast(v).*, @constCast(n).*) * 2);
}

pub fn refract(uv: *const @Vector(3, f32), n: @Vector(3, f32), etai_over_etat: f32) @Vector(3, f32) {
    const cos_theta: f32 = @min(dot((-uv.*), n), 1.0);
    const r_out_perp = scale(uv.* + scale(n, cos_theta), etai_over_etat);
    const r_out_parallel = scale(n, -@sqrt(@abs(1.0 - square_magnitude(r_out_perp))));
    return r_out_perp + r_out_parallel;
}

pub fn dot(u: @Vector(3, f32), v: @Vector(3, f32)) f32 {
    return (u[0] * v[0] + u[1] * v[1] + u[2] * v[2]);
}

pub fn cross(u: @Vector(3, f32), v: @Vector(3, f32)) @Vector(3, f32) {
    return init(u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]);
}

pub const OrthonormalBasis = struct {
    u: @Vector(3, f32),
    v: @Vector(3, f32),
    w: @Vector(3, f32),

    pub fn init(n: @Vector(3, f32)) OrthonormalBasis {
        const w = unit(n);
        const a = if (@abs(w[0]) > 0.9) @Vector(3, f32){ 0, 1, 0 } else @Vector(3, f32){ 1, 0, 0 };
        const v = unit(cross(w, a));
        const u = cross(w, v);

        return .{ .u = u, .v = v, .w = w };
    }

    pub fn transform(self: OrthonormalBasis, v: @Vector(3, f32)) @Vector(3, f32) {
        const scaled_u = self.u * @as(@Vector(3, f32), @splat(v[0]));
        const scaled_v = self.v * @as(@Vector(3, f32), @splat(v[1]));
        const scaled_w = self.w * @as(@Vector(3, f32), @splat(v[2]));

        return scaled_u + scaled_v + scaled_w;
    }
};

pub const Interval = struct {
    min: f32,
    max: f32,
    const Self = @This();

    pub fn init(min: f32, max: f32) Self {
        return Self{
            .min = min,
            .max = max,
        };
    }

    pub fn empty() Self {
        return Self{
            .min = std.math.inf(f32),
            .max = -std.math.inf(f32),
        };
    }

    pub fn universe() Self {
        return Self{
            .min = -std.math.inf(f32),
            .max = std.math.inf(f32),
        };
    }

    pub fn add(self: Interval, displacement: f32) Interval {
        return .{ .min = self.min + displacement, .max = self.max + displacement };
    }

    pub fn size(self: Self) f32 {
        return self.max - self.min;
    }

    pub fn contains(self: Self, x: f32) bool {
        return self.min <= x and x <= self.max;
    }

    pub fn surrounds(self: Self, x: f32) bool {
        return self.min < x and x < self.max;
    }

    pub fn clamp(self: Self, x: f32) f32 {
        if (x < self.min) return self.min;
        if (x > self.max) return self.max;
        return x;
    }

    pub fn expand(self: Self, delta: f32) Self {
        const padding = delta / 2.0;
        return Self{
            .min = self.min - padding,
            .max = self.max + padding,
        };
    }

    pub fn merge(a: Self, b: Self) Self {
        return Self{
            .min = @min(a.min, b.min),
            .max = @max(a.max, b.max),
        };
    }
};

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
            if (direction[0] != 0.0) 1.0 / direction[0] else std.math.inf(f32),
            if (direction[1] != 0.0) 1.0 / direction[1] else std.math.inf(f32),
            if (direction[2] != 0.0) 1.0 / direction[2] else std.math.inf(f32),
        };
    }

    pub fn position(self: Ray, t: f32) @Vector(3, f32) {
        return self.origin + scale(self.direction, t);
    }
};
