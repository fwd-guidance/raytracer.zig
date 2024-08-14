pub const std = @import("std");
const math = std.math;

pub const color = @import("color.zig");

pub const ray = @import("ray.zig");
pub const Ray = ray.Ray;

pub const vec = @import("vec.zig");
pub const init = vec.init;

pub const hittable = @import("hittable.zig");
pub const hit_record = hittable.hit_record;

pub const sphere = @import("sphere.zig");
pub const Sphere = sphere.sphere;

pub const HittableList = @import("hittable_list.zig");

pub const interval = @import("interval.zig");
pub const Interval = interval.Interval;

pub const camera = @import("camera.zig");
pub const Camera = camera.Camera;

pub const material = @import("material.zig");
pub const Material = material.Material;

pub const AABB = @import("aabb.zig");
pub const aabb = AABB.aabb;

pub fn random_double() f64 {
    const rand = std.crypto.random;
    return rand.float(f64);
}

pub fn random_double_range(min: f64, max: f64) f64 {
    return min + (max - min) * random_double();
}
