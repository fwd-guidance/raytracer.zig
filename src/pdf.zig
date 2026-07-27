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

    pub fn value(self: *const PDF, direction: @Vector(3, f32)) f32 {
        return switch (self.*) {
            .sphere => |*s| s.spherepdf_value(direction),
            .cosine => |*c| c.cosinepdf_value(direction),
            .hittable => |*h| h.hittablepdf_value(direction),
            .mixture => |*m| m.mixturepdf_value(direction),
        };
    }

    pub fn generate(self: *const PDF) @Vector(3, f32) {
        return switch (self.*) {
            .sphere => |*s| s.spherepdf_generate(),
            .cosine => |*c| c.cosinepdf_generate(),
            .hittable => |*h| h.hittablepdf_generate(),
            .mixture => |*m| m.mixturepdf_generate(),
        };
    }
};

pub const SpherePDF = struct {
    pub fn init() SpherePDF {
        return .{};
    }

    pub fn spherepdf_value(self: *const SpherePDF, direction: @Vector(3, f32)) f32 {
        _ = self;
        _ = direction;
        return 1.0 / (4 * std.math.pi);
    }

    pub fn spherepdf_generate(self: *const SpherePDF) @Vector(3, f32) {
        _ = self;
        return math.random_unit_vector();
    }
};

pub const CosinePDF = struct {
    w: @Vector(3, f32),

    pub fn init(w: @Vector(3, f32)) CosinePDF {
        return .{ .w = math.unit(w) };
    }

    pub fn cosinepdf_value(self: *const CosinePDF, direction: @Vector(3, f32)) f32 {
        const cosine_theta = math.dot(math.unit(direction), self.w);
        return @max(0, cosine_theta / std.math.pi);
    }

    pub fn cosinepdf_generate(self: *const CosinePDF) @Vector(3, f32) {
        // Only rebuild u/v here, where they're actually needed.
        const onb = math.OrthonormalBasis.init(self.w);
        return onb.transform(math.random_cosine_direction());
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

    pub fn hittablepdf_value(self: *const HittablePDF, direction: @Vector(3, f32)) f32 {
        return self.objects.pdf_value(self.origin, direction);
    }

    pub fn hittablepdf_generate(self: *const HittablePDF) @Vector(3, f32) {
        return self.objects.random(self.origin);
    }
};

pub const MixturePDF = struct {
    p: [2]*const PDF,

    pub fn init(p0: *const PDF, p1: *const PDF) MixturePDF {
        return .{ .p = .{ p0, p1 } };
    }

    pub fn mixturepdf_value(self: *const MixturePDF, direction: @Vector(3, f32)) f32 {
        return 0.5 * self.p[0].value(direction) + 0.5 * self.p[1].value(direction);
    }

    pub fn mixturepdf_generate(self: *const MixturePDF) @Vector(3, f32) {
        if (utils.random_double() < 0.5) {
            return self.p[0].generate();
        } else {
            return self.p[1].generate();
        }
    }
};
