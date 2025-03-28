const rtw = @import("rtweekend.zig");
const random_double = rtw.random_double;
const random_double_range = rtw.random_double_range;
const std = rtw.std;

pub fn init(x: f32, y: f32, z: f32) @Vector(3, f32) {
    return @Vector(3, f32){ x, y, z };
}

pub fn random_vec() @Vector(3, f32) {
    return @Vector(3, f32){ random_double(), random_double(), random_double() };
}

pub fn random_vec_range(min: f32, max: f32) @Vector(3, f32) {
    return @Vector(3, f32){ random_double_range(min, max), random_double_range(min, max), random_double_range(min, max) };
}

pub fn add(v: @Vector(3, f32), scalar: f32) !@Vector(3, f32) {
    return v + init(scalar, scalar, scalar);
}

pub fn scale(v: @Vector(3, f32), scalar: f32) !@Vector(3, f32) {
    return v * init(scalar, scalar, scalar);
}

pub fn invert(v: @Vector(3, f32)) !@Vector(3, f32) {
    return v * init(-1, -1, -1);
}

pub fn magnitude(v: @Vector(3, f32)) !f32 {
    //return @sqrt(std.math.pow(f32, v[0], 2) + std.math.pow(f32, v[1], 2) + std.math.pow(f32, v[2], 2));
    return @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
}

pub fn square_magnitude(v: @Vector(3, f32)) !f32 {
    //return std.math.pow(f32, v[0], 2) + std.math.pow(f32, v[1], 2) + std.math.pow(f32, v[2], 2);
    return v[0] * v[0] + v[1] * v[1] + v[2] * v[2];
}

pub fn near_zero(self: @Vector(3, f32)) !bool {
    const s: f32 = 1e-8;
    return (@abs(self[0]) < s) and (@abs(self[1]) < s) and (@abs(self[2]) < s);
}

pub fn unit(v: @Vector(3, f32)) !@Vector(3, f32) {
    return v / init(try magnitude(v), try magnitude(v), try magnitude(v));
}

pub fn random_in_unit_disk() !@Vector(3, f32) {
    while (true) {
        const p = @Vector(3, f32){ random_double_range(-1, 1), random_double_range(-1, 1), 0 };
        if (try square_magnitude(p) < 1) return p;
    }
}

pub fn random_in_unit_sphere() !@Vector(3, f32) {
    while (true) {
        const p = random_vec_range(-1, 1);
        if (try square_magnitude(p) < 1) return p;
    }
}

pub fn random_unit_vector() @Vector(3, f32) {
    return try unit(try random_in_unit_sphere());
}

pub fn random_on_hemisphere(normal: @Vector(3, f32)) !@Vector(3, f32) {
    const on_unit_sphere = random_unit_vector();
    if (try dot(on_unit_sphere, normal) > 0.0) {
        return on_unit_sphere;
    } else {
        return try invert(on_unit_sphere);
    }
}

pub fn reflect(v: *const @Vector(3, f32), n: *const @Vector(3, f32)) !@Vector(3, f32) {
    return @constCast(v).* - try scale(@constCast(n).*, try dot(@constCast(v).*, @constCast(n).*) * 2);
}

pub fn refract(uv: *const @Vector(3, f32), n: @Vector(3, f32), etai_over_etat: f32) !@Vector(3, f32) {
    const cos_theta: f32 = @min(try dot(try invert(uv.*), n), 1.0);
    const r_out_perp = try scale(uv.* + try scale(n, cos_theta), etai_over_etat);
    const r_out_parallel = try scale(n, -@sqrt(@abs(1.0 - try square_magnitude(r_out_perp))));
    return r_out_perp + r_out_parallel;
}

pub fn dot(u: @Vector(3, f32), v: @Vector(3, f32)) !f32 {
    return (u[0] * v[0] + u[1] * v[1] + u[2] * v[2]);
}

pub fn cross(u: @Vector(3, f32), v: @Vector(3, f32)) !@Vector(3, f32) {
    return init(u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]);
}
