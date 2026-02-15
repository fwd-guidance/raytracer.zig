const std = @import("std");

const math = @import("math.zig");
const scene = @import("scene.zig");
const HittableList = scene.HittableList;

pub const PDF = union(enum) {
    SpherePDF,
    CosinePDF,
    HittablePDF,

    pub fn init() PDF {
        return switch (PDF) {
            .SpherePDF => |s| s.init(),
            .CosinePDF => |c| c.init(),
            .HittablePDF => |h| h.init(),
        };
    }

    pub fn value(direction: *const @Vector(3, f32)) f32 {
        return switch (PDF) {
            .SpherePDF => |s| s.value(direction),
            .CosinePDF => |c| c.value(direction),
            .HittablePDF => |h| h.value(direction),
        };
    }

    pub fn generate() @Vector(3, f32) {
        return switch (PDF) {
            .SpherePDF => |s| s.generate(),
            .CosinePDF => |c| c.generate(),
            .HittablePDF => |h| h.generate(),
        };
    }
};

pub const SpherePDF = struct {
    pub fn init() SpherePDF {
        return .{};
    }

    pub fn value(direction: *const @Vector(3, f32)) f32 {
        _ = direction;
        return 1 / (4 * std.math.pi);
    }

    pub fn generate() @Vector(3, f32) {
        return math.random_unit_vector();
    }
};

pub const CosinePDF = struct {
    uvw: math.OrthonormalBasis,

    pub fn init(w: @Vector(3, f32)) CosinePDF {
        return .{ .uvw = math.OrthonormalBasis.init(w) };
    }

    pub fn value(self: CosinePDF, direction: *const @Vector(3, f32)) f32 {
        const cosine_theta = math.dot(math.unit(direction.*), self.uvw.w);
        return @max(0, cosine_theta / std.math.pi);
    }

    pub fn generate(self: CosinePDF) @Vector(3, f32) {
        return self.uvw.transform(math.random_cosine_direction());
    }
};

pub const HittablePDF = struct {
    objects: *const HittableList,
    origin: @Vector(3, f32),

    pub fn init(objects: *const HittableList, origin: @Vector(3, f32)) HittablePDF {
        return .{
            .objects = objects,
            .origin = origin,
        };
    }

    pub fn value(self: *const HittablePDF, direction: @Vector(3, f32)) f32 {
        return self.objects.pdf_value(self.origin, direction);
    }

    pub fn generate(self: *const HittablePDF) @Vector(3, f32) {
        return self.objects.random(self.origin);
    }
};
