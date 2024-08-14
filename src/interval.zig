pub const Interval = struct {
    min: f64,
    max: f64,
    const Self = @This();

    pub fn init(a: *const Self, b: *const Self) Interval {
        return Interval{ .min = if (a.min <= b.min) a.min else b.min, .max = if (a.max >= b.max) a.max else b.max };
    }

    pub fn size(self: Self) f64 {
        return self.max - self.min;
    }

    pub fn contains(self: Self, x: f64) bool {
        return self.min <= x and x <= self.max;
    }

    pub fn surrounds(self: Self, x: f64) bool {
        return self.min < x and x < self.max;
    }

    pub fn clamp(self: Self, x: f64) f64 {
        if (x < self.min) return self.min;
        if (x > self.max) return self.max;
        return x;
    }

    pub fn expand(self: Self, delta: f64) Interval {
        const padding: f64 = delta / 2;
        return Interval{ .min = self.min - padding, .max = self.max + padding };
    }
};
