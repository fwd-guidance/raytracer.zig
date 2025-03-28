const std = @import("std");

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
