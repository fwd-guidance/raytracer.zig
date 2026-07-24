const std = @import("std");
const utils = @import("utils.zig");

const Texture = @import("texture.zig").Texture;
const math = @import("math.zig");
const Ray = math.Ray;

const scene = @import("scene.zig");
const HitRecord = scene.HitRecord;

const pdf = @import("pdf.zig");
const PDF = pdf.PDF;

pub const ScatterRecord = struct {
    attenuation: @Vector(3, f32),
    pdf_value: ?PDF,
    skip_pdf: bool,
    skip_pdf_ray: Ray,
};

pub const Material = union(enum) {
    Lambertian: Lambertian,
    Metal: Metal,
    Dielectric: Dielectric,
    DiffuseLight: DiffuseLight,
    Isotropic: Isotropic,

    pub fn lambertian(tex_id: usize) Material {
        return Material{ .Lambertian = Lambertian{ .tex_id = tex_id } };
    }

    pub fn metal(albedo: @Vector(3, f32), fuzz: f32) Material {
        return Material{ .Metal = Metal{ .albedo = albedo, .fuzz = fuzz } };
    }

    pub fn dielectric(refraction_index: f32) Material {
        return Material{ .Dielectric = Dielectric.init(refraction_index) };
    }

    pub fn diffuse_light(tex_id: usize) Material {
        return Material{ .DiffuseLight = DiffuseLight{ .tex_id = tex_id } };
    }

    pub fn isotropic(tex_id: usize) Material {
        return Material{ .Isotropic = Isotropic{ .tex_id = tex_id } };
    }

    pub fn scatter(self: Material, r_in: *const Ray, rec: *const HitRecord, srec: *ScatterRecord, textures: []const Texture) bool {
        return switch (self) {
            .Lambertian => |l| l.scatter(r_in, rec, srec, textures),
            .Metal => |m| m.scatter(r_in, rec, srec),
            .Dielectric => |d| d.scatter(r_in, rec, srec),
            .DiffuseLight => false,
            .Isotropic => |i| i.scatter(r_in, rec, srec, textures),
        };
    }

    pub fn emitted(self: Material, r_in: *const Ray, rec: *const HitRecord, u: f32, v: f32, p: @Vector(3, f32), textures: []const Texture) @Vector(3, f32) {
        return switch (self) {
            .DiffuseLight => |d| d.emitted(r_in, rec, u, v, p, textures),
            else => @Vector(3, f32){ 0, 0, 0 },
        };
    }

    pub fn scattering_pdf(self: Material, r_in: *const Ray, rec: *const HitRecord, scattered: *const Ray) f32 {
        return switch (self) {
            .Lambertian => |l| l.scattering_pdf(r_in, rec, scattered),
            .Isotropic => |i| i.scattering_pdf(r_in, rec, scattered),
            else => 0.0,
        };
    }
};

pub const Lambertian = struct {
    tex_id: usize,

    pub fn scatter(self: Lambertian, r_in: *const Ray, rec: *const HitRecord, srec: *ScatterRecord, textures: []const Texture) bool {
        _ = r_in;
        const texture = textures[self.tex_id];

        srec.*.attenuation = texture.value(rec.u, rec.v, rec.p);
        srec.*.pdf_value = pdf.PDF{ .cosine = pdf.CosinePDF.init(rec.normal) };
        srec.*.skip_pdf = false;
        return true;
    }

    pub fn scattering_pdf(self: Lambertian, r_in: *const Ray, rec: *const HitRecord, scattered: *const Ray) f32 {
        _ = r_in;
        _ = self;
        const cos_theta = math.dot(rec.normal, math.unit(scattered.direction));
        if (cos_theta < 0) return 0 else return cos_theta / std.math.pi;
    }
};

pub const Metal = struct {
    albedo: @Vector(3, f32),
    fuzz: f32,

    pub fn scatter(self: Metal, r_in: *const Ray, rec: *const HitRecord, srec: *ScatterRecord) bool {
        var reflected = math.reflect(r_in.direction, rec.normal);
        reflected = math.unit(reflected) + (math.scale(math.random_unit_vector(), self.fuzz));
        srec.*.attenuation = self.albedo;
        srec.*.pdf_value = null;
        srec.*.skip_pdf = true;
        srec.*.skip_pdf_ray = Ray.init(rec.*.p, reflected, r_in.*.tm);
        return true;
    }
};

pub const Dielectric = struct {
    refraction_index: f32,
    r0: f32,
    one_minus_r0: f32,

    pub fn init(refraction_index: f32) Dielectric {
        const r0_temp = (1.0 - refraction_index) / (1.0 + refraction_index);
        const r0_val = r0_temp * r0_temp;
        return .{
            .refraction_index = refraction_index,
            .r0 = r0_val,
            .one_minus_r0 = 1.0 - r0_val,
        };
    }

    pub fn scatter(self: Dielectric, r_in: *const Ray, rec: *const HitRecord, srec: *ScatterRecord) bool {
        srec.*.attenuation = @Vector(3, f32){ 1.0, 1.0, 1.0 };
        srec.*.pdf_value = null;
        srec.*.skip_pdf = true;

        const ri: f32 = if (rec.*.front_face) 1.0 / self.refraction_index else self.refraction_index;
        const unit_direction = math.unit(r_in.*.direction);
        const cos_theta: f32 = @min(math.dot(-(unit_direction), rec.*.normal), 1.0);
        const sin_theta: f32 = @sqrt(1.0 - cos_theta * cos_theta);

        const cannot_refract: bool = (ri * sin_theta) > 1.0;
        var direction: @Vector(3, f32) = undefined;

        if (cannot_refract or (self.reflectance(cos_theta) > utils.random_double())) {
            direction = math.reflect(unit_direction, rec.*.normal);
        } else {
            direction = math.refract(unit_direction, rec.*.normal, ri);
        }

        srec.*.skip_pdf_ray = Ray.init(rec.*.p, direction, r_in.*.tm);
        return true;
    }

    fn reflectance(self: Dielectric, cosine: f32) f32 {
        const one_minus = 1 - cosine;
        const sq = one_minus * one_minus;
        return self.r0 + self.one_minus_r0 * (sq * sq * one_minus);
    }
};

pub const DiffuseLight = struct {
    tex_id: usize,

    pub fn emitted(self: DiffuseLight, r_in: *const Ray, rec: *const HitRecord, u: f32, v: f32, p: @Vector(3, f32), textures: []const Texture) @Vector(3, f32) {
        _ = r_in;
        if (!rec.*.front_face) return math.init(0, 0, 0);
        return textures[self.tex_id].value(u, v, p);
    }
};

pub const Isotropic = struct {
    tex_id: usize,

    pub fn scatter(self: Isotropic, r_in: *const Ray, rec: *const HitRecord, srec: *ScatterRecord, textures: []const Texture) bool {
        _ = r_in;
        const texture = textures[self.tex_id];
        srec.*.attenuation = texture.value(rec.*.u, rec.*.v, rec.*.p);
        srec.*.pdf_value = pdf.PDF{ .sphere = pdf.SpherePDF.init() };
        srec.*.skip_pdf = false;
        return true;
    }

    pub fn scattering_pdf(self: Isotropic, r_in: *const Ray, rec: *const HitRecord, scattered: *const Ray) f32 {
        _ = self;
        _ = r_in;
        _ = rec;
        _ = scattered;
        return 1.0 / (4 * std.math.pi);
    }
};
