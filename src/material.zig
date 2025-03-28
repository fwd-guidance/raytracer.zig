const rtw = @import("rtweekend.zig");

const Ray = rtw.Ray;
const hit_record = rtw.hit_record;

pub const Material = union(enum) {
    Lambertian: Lambertian,
    Metal: Metal,
    Dielectric: Dielectric,

    pub fn lambertian(albedo: @Vector(3, f32)) Material {
        return Material{ .Lambertian = Lambertian{ .albedo = albedo } };
    }

    pub fn metal(albedo: @Vector(3, f32), fuzz: f32) Material {
        return Material{ .Metal = Metal{ .albedo = albedo, .fuzz = fuzz } };
    }

    pub fn dielectric(refraction_index: f32) Material {
        return Material{ .Dielectric = Dielectric{ .refraction_index = refraction_index } };
    }
};

pub const Lambertian = struct {
    albedo: @Vector(3, f32),
    const Self = @This();

    pub fn scatter(self: Self, r_in: *const Ray, rec: *const hit_record, attenuation: *@Vector(3, f32), scattered: *Ray) !bool {
        var scatter_direction: @Vector(3, f32) = rec.*.normal + rtw.vec.random_unit_vector();

        if (try rtw.vec.near_zero(scatter_direction)) scatter_direction = rec.*.normal;
        scattered.* = Ray{ .origin = rec.*.p, .direction = scatter_direction, .tm = r_in.*.tm };
        attenuation.* = self.albedo;
        return true;
    }
};

pub const Metal = struct {
    albedo: @Vector(3, f32),
    fuzz: f32,
    const Self = @This();

    pub fn scatter(self: Self, r_in: *const Ray, rec: *const hit_record, attenuation: *@Vector(3, f32), scattered: *Ray) !bool {
        var reflected = try rtw.vec.reflect(&r_in.direction, &rec.normal);
        reflected = try rtw.vec.unit(reflected) + (try rtw.vec.scale(rtw.vec.random_unit_vector(), self.fuzz));
        scattered.* = Ray{ .origin = rec.*.p, .direction = reflected, .tm = r_in.*.tm };
        attenuation.* = self.albedo;
        return try rtw.vec.dot(scattered.*.direction, rec.*.normal) > 0;
    }
};

pub const Dielectric = struct {
    refraction_index: f32,
    const Self = @This();

    pub fn scatter(self: Self, r_in: *const Ray, rec: *const hit_record, attenuation: *@Vector(3, f32), scattered: *Ray) !bool {
        attenuation.* = @Vector(3, f32){ 1.0, 1.0, 1.0 };
        const ri: f32 = if (rec.*.front_face) 1.0 / self.refraction_index else self.refraction_index;
        const unit_direction = try rtw.vec.unit(r_in.*.direction);
        const cos_theta: f32 = @min(try rtw.vec.dot(try rtw.vec.invert(unit_direction), rec.*.normal), 1.0);
        const sin_theta: f32 = @sqrt(1.0 - cos_theta * cos_theta);

        const cannot_refract: bool = (ri * sin_theta) > 1.0;
        var direction: @Vector(3, f32) = undefined;

        if (cannot_refract or (try reflectance(cos_theta, ri) > rtw.random_double())) {
            direction = try rtw.vec.reflect(&unit_direction, &rec.*.normal);
        } else {
            direction = try rtw.vec.refract(&unit_direction, rec.*.normal, ri);
        }

        scattered.* = Ray{ .origin = rec.*.p, .direction = direction, .tm = r_in.*.tm };
        return true;
    }

    fn reflectance(cosine: f32, refraction_index: f32) !f32 {
        var r0: f32 = (1 - refraction_index) / (1 + refraction_index);
        r0 = r0 * r0;
        //return r0 + (1 - r0) * rtw.std.math.pow(f32, (1 - cosine), 5);
        return r0 + (1 - r0) * ((1 - cosine) * (1 - cosine) * (1 - cosine) * (1 - cosine) * (1 - cosine));
    }
};
