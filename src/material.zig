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
        return Material{ .Dielectric = Dielectric.init(refraction_index) };
    }
};

pub const Lambertian = struct {
    albedo: @Vector(3, f32),
    const Self = @This();

    pub fn scatter(self: Self, r_in: *const Ray, rec: *const hit_record, attenuation: *@Vector(3, f32), scattered: *Ray) bool {
        const scatter_direction: @Vector(3, f32) = rec.*.normal + rtw.vec.random_unit_vector();
        scattered.* = Ray.init(rec.*.p, scatter_direction, r_in.*.tm);
        attenuation.* = self.albedo;
        return true;
    }
};

pub const Metal = struct {
    albedo: @Vector(3, f32),
    fuzz: f32,
    const Self = @This();

    pub fn scatter(self: Self, r_in: *const Ray, rec: *const hit_record, attenuation: *@Vector(3, f32), scattered: *Ray) bool {
        var reflected = rtw.vec.reflect(&r_in.direction, &rec.normal);
        reflected = rtw.vec.unit(reflected) + (rtw.vec.scale(rtw.vec.random_unit_vector(), self.fuzz));
        scattered.* = Ray.init(rec.*.p, reflected, r_in.*.tm);
        attenuation.* = self.albedo;
        return rtw.vec.dot(scattered.*.direction, rec.*.normal) > 0;
    }
};

pub const Dielectric = struct {
    refraction_index: f32,
    r0: f32,
    one_minus_r0: f32,
    const Self = @This();

    pub fn init(refraction_index: f32) Self {
        const r0_temp = (1.0 - refraction_index) / (1.0 + refraction_index);
        const r0_val = r0_temp * r0_temp;
        return Self{
            .refraction_index = refraction_index,
            .r0 = r0_val,
            .one_minus_r0 = 1.0 - r0_val,
        };
    }

    pub fn scatter(self: Self, r_in: *const Ray, rec: *const hit_record, attenuation: *@Vector(3, f32), scattered: *Ray) bool {
        attenuation.* = @Vector(3, f32){ 1.0, 1.0, 1.0 };
        const ri: f32 = if (rec.*.front_face) 1.0 / self.refraction_index else self.refraction_index;
        const unit_direction = rtw.vec.unit(r_in.*.direction);
        const cos_theta: f32 = @min(rtw.vec.dot(rtw.vec.invert(unit_direction), rec.*.normal), 1.0);
        const sin_theta: f32 = @sqrt(1.0 - cos_theta * cos_theta);

        const cannot_refract: bool = (ri * sin_theta) > 1.0;
        var direction: @Vector(3, f32) = undefined;

        if (cannot_refract or (self.reflectance(cos_theta) > rtw.random_double())) {
            direction = rtw.vec.reflect(&unit_direction, &rec.*.normal);
        } else {
            direction = rtw.vec.refract(&unit_direction, rec.*.normal, ri);
        }

        scattered.* = Ray.init(rec.*.p, direction, r_in.*.tm);
        return true;
    }

    fn reflectance(self: Self, cosine: f32) f32 {
        const one_minus = 1 - cosine;
        const sq = one_minus * one_minus;
        return self.r0 + self.one_minus_r0 * (sq * sq * one_minus);
    }
};
