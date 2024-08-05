const std = @import("std");

pub const vec = struct {
    x: f64,
    y: f64,
    z: f64,

    pub fn init(x: f64, y: f64, z: f64) @Vector(3, f64) {
        return @Vector(3, f64){ x, y, z };
    }

    pub fn add(v: @Vector(3, f64), scalar: f64) !@Vector(3, f64) {
        return v + vec.init(scalar, scalar, scalar);
    }

    pub fn scale(v: @Vector(3, f64), scalar: f64) !@Vector(3, f64) {
        return v * vec.init(scalar, scalar, scalar);
    }

    pub fn invert(v: @Vector(3, f64)) !@Vector(3, f64) {
        return v * vec.init(-1, -1, -1);
    }

    pub fn magnitude(v: @Vector(3, f64)) !f64 {
        return @sqrt(std.math.pow(f64, v[0], 2) + std.math.pow(f64, v[1], 2) + std.math.pow(f64, v[2], 2));
    }

    pub fn square_magnitude(v: @Vector(3, f64)) !f64 {
        return std.math.pow(f64, v[0], 2) + std.math.pow(f64, v[1], 2) + std.math.pow(f64, v[2], 2);
    }

    pub fn unit(v: @Vector(3, f64)) !@Vector(3, f64) {
        return v / vec.init(try vec.magnitude(v), try vec.magnitude(v), try vec.magnitude(v));
    }

    pub fn dot(u: @Vector(3, f64), v: @Vector(3, f64)) !f64 {
        return (u[0] * v[0] + u[1] * v[1] + u[2] * v[2]);
    }

    pub fn cross(u: @Vector(3, f64), v: @Vector(3, f64)) !@Vector(3, f64) {
        return vec.init(u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]);
    }
};
