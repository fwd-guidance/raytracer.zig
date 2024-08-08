pub const Interval = struct {
    min: f64,
    max: f64,
    const Self = @This();

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
};
