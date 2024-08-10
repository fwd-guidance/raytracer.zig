const rtw = @import("rtweekend.zig");

const Ray = rtw.Ray;
const hit_record = rtw.hit_record;

pub const Result = struct {
    ok: bool,
    scattered: Ray,
    attenuation: @Vector(3, f64),
};

pub const Material = union(enum) {
    Lambertian: Lambertian,
    Metal: Metal,
    Dielectric: Dielectric,

    pub fn lambertian(albedo: @Vector(3, f64)) Material {
        return Material{ .Lambertian = Lambertian{ .albedo = albedo } };
    }

    pub fn metal(albedo: @Vector(3, f64), fuzz: f64) Material {
        return Material{ .Metal = Metal{ .albedo = albedo, .fuzz = fuzz } };
    }

    pub fn dielectric(refraction_index: f64) Material {
        return Material{ .Dielectric = Dielectric{ .refraction_index = refraction_index } };
    }
};
//pub fn scatter(r_in: *const Ray, rec: *const hit_record, attenuation: *@Vector(3, f64), scattered: *Ray) !bool {
//    return false;
//}
//};

pub const Lambertian = struct {
    albedo: @Vector(3, f64),
    const Self = @This();

    pub fn scatter(self: Self, r_in: *const Ray, rec: *const hit_record, attenuation: *@Vector(3, f64), scattered: *Ray) !Result {
        _ = r_in;
        var scatter_direction: @Vector(3, f64) = rec.*.normal + rtw.vec.random_unit_vector();

        if (try rtw.vec.near_zero(scatter_direction)) scatter_direction = rec.*.normal;
        scattered.* = Ray{ .origin = rec.*.p, .direction = scatter_direction };
        attenuation.* = self.albedo;
        //rtw.std.debug.print("scattered = {}\n", .{scattered.*});
        //rtw.std.debug.print("attenuation = {}\n", .{attenuation.*});
        return Result{ .ok = true, .scattered = scattered.*, .attenuation = attenuation.* };
    }
};

pub const Metal = struct {
    albedo: @Vector(3, f64),
    fuzz: f64,
    const Self = @This();

    pub fn scatter(self: Self, r_in: *const Ray, rec: *const hit_record, attenuation: *@Vector(3, f64), scattered: *Ray) !Result {
        var reflected = try rtw.vec.reflect(&r_in.direction, &rec.normal);
        reflected = try rtw.vec.unit(reflected) + (try rtw.vec.scale(rtw.vec.random_unit_vector(), self.fuzz));
        scattered.* = Ray{ .origin = rec.*.p, .direction = reflected };
        attenuation.* = self.albedo;

        return Result{ .ok = (try rtw.vec.dot(scattered.*.direction, rec.*.normal) > 0), .scattered = scattered.*, .attenuation = attenuation.* };
    }
};

pub const Dielectric = struct {
    refraction_index: f64,
    const Self = @This();

    pub fn scatter(self: Self, r_in: *const Ray, rec: *const hit_record, attenuation: *@Vector(3, f64), scattered: *Ray) !Result {
        attenuation.* = @Vector(3, f64){ 1.0, 1.0, 1.0 };
        const ri: f64 = if (rec.*.front_face) 1.0 / self.refraction_index else self.refraction_index;
        const unit_direction = try rtw.vec.unit(r_in.*.direction);
        const cos_theta: f64 = @min(try rtw.vec.dot(try rtw.vec.invert(unit_direction), rec.*.normal), 1.0);
        const sin_theta: f64 = @sqrt(1.0 - cos_theta * cos_theta);

        const cannot_refract: bool = (ri * sin_theta) > 1.0;
        var direction: @Vector(3, f64) = undefined;

        if (cannot_refract or (try reflectance(cos_theta, ri) > rtw.random_double())) {
            direction = try rtw.vec.reflect(&unit_direction, &rec.*.normal);
        } else {
            direction = try rtw.vec.refract(&unit_direction, rec.*.normal, ri);
        }

        scattered.* = Ray{ .origin = rec.*.p, .direction = direction };
        //rtw.std.debug.print("SCATTERED = {any}\n", .{scattered.*});
        //rtw.std.debug.print("ATTENUATION = {any}\n", .{attenuation.*});
        return Result{ .ok = true, .scattered = scattered.*, .attenuation = attenuation.* };
    }

    fn reflectance(cosine: f64, refraction_index: f64) !f64 {
        var r0: f64 = (1 - refraction_index) / (1 + refraction_index);
        r0 = r0 * r0;
        return r0 + (1 - r0) * rtw.std.math.pow(f64, (1 - cosine), 5);
    }
};
