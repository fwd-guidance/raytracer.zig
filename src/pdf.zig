const std = @import("std");

const utils = @import("utils.zig");
const math = @import("math.zig");
const scene = @import("scene.zig");
const HittableList = scene.HittableList;

pub const PDF = union(enum) {
    sphere: SpherePDF,
    cosine: CosinePDF,
    hittable: HittablePDF,
    mixture: MixturePDF,

    pub fn init() PDF {
        return switch (PDF) {
            .sphere => |s| s.init(),
            .cosine => |c| c.init(),
            .hittable => |h| h.init(),
            .mixture => |m| m.init(),
        };
    }

    pub fn value(self: *const PDF, direction: @Vector(3, f32)) f32 {
        return switch (self.*) {
            .sphere => |s| s.value(direction),
            .cosine => |c| c.value(direction),
            .hittable => |h| h.value(direction),
            .mixture => |m| m.value(direction),
        };
    }

    pub fn generate(self: *const PDF) @Vector(3, f32) {
        return switch (self.*) {
            .sphere => |s| s.generate(),
            .cosine => |c| c.generate(),
            .hittable => |h| h.generate(),
            .mixture => |m| m.generate(),
        };
    }
};

pub const SpherePDF = struct {
    pub fn init() SpherePDF {
        return .{};
    }

    pub fn value(self: *const SpherePDF, direction: @Vector(3, f32)) f32 {
        _ = self;
        _ = direction;
        return 1.0 / (4 * std.math.pi);
    }

    pub fn generate(self: *const SpherePDF) @Vector(3, f32) {
        _ = self;
        return math.random_unit_vector();
    }
};

pub const CosinePDF = struct {
    uvw: math.OrthonormalBasis,

    pub fn init(w: @Vector(3, f32)) CosinePDF {
        return .{ .uvw = math.OrthonormalBasis.init(w) };
    }

    pub fn value(self: CosinePDF, direction: @Vector(3, f32)) f32 {
        const cosine_theta = math.dot(math.unit(direction), self.uvw.w);
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

pub const MixturePDF = struct {
    p: [2]*const PDF,

    pub fn init(p0: *const PDF, p1: *const PDF) MixturePDF {
        return .{ .p = .{ p0, p1 } };
    }

    pub fn value(self: *const MixturePDF, direction: @Vector(3, f32)) f32 {
        return 0.5 * self.p[0].value(direction) + 0.5 * self.p[1].value(direction);
    }

    pub fn generate(self: *const MixturePDF) @Vector(3, f32) {
        if (utils.random_double() < 0.5) {
            return self.p[0].generate();
        } else {
            return self.p[1].generate();
        }
    }
};
