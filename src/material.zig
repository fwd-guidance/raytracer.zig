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
    //fuzz: ?f64,

    pub fn lambertian(albedo: @Vector(3, f64)) Material {
        return Material{ .Lambertian = Lambertian{ .albedo = albedo } };
    }

    pub fn metal(albedo: @Vector(3, f64), fuzz: f64) Material {
        return Material{ .Metal = Metal{ .albedo = albedo, .fuzz = fuzz } };
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
