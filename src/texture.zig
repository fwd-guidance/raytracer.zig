const RTWImage = @import("rtw_stb_image.zig").RTWImage;

pub const Texture = union(enum) {
    SolidColor: SolidColor,
    Checker: Checker,
    Image: Image,

    pub fn solid_color(albedo: @Vector(3, f32)) Texture {
        return .{ .SolidColor = SolidColor{ .albedo = albedo } };
    }

    pub fn checker(scale: f32, even: *const Texture, odd: *const Texture) Texture {
        return .{ .Checker = Checker{ .inv_scale = 1.0 / scale, .even = even, .odd = odd } };
    }

    pub fn image(img: *const RTWImage) Texture {
        return .{ .Image = Image{ .image = img } };
    }

    pub fn value(self: *const Texture, u: f32, v: f32, p: @Vector(3, f32)) @Vector(3, f32) {
        return switch (self.*) {
            .SolidColor => |sc| sc.value(u, v, p),
            .Checker => |c| c.value(u, v, p),
            .Image => |i| i.value(u, v, p),
        };
    }
};

pub const SolidColor = struct {
    albedo: @Vector(3, f32),

    pub fn value(self: SolidColor, u: f32, v: f32, p: @Vector(3, f32)) @Vector(3, f32) {
        _ = u;
        _ = v;
        _ = p;
        return self.albedo;
    }
};

pub const Checker = struct {
    inv_scale: f32,
    even: *const Texture,
    odd: *const Texture,

    pub fn value(self: Checker, u: f32, v: f32, p: @Vector(3, f32)) @Vector(3, f32) {
        const x = @as(i32, @intFromFloat(@floor(self.inv_scale * p[0])));
        const y = @as(i32, @intFromFloat(@floor(self.inv_scale * p[1])));
        const z = @as(i32, @intFromFloat(@floor(self.inv_scale * p[2])));

        const is_even = @mod(x + y + z, 2) == 0;

        return if (is_even) self.even.value(u, v, p) else self.odd.value(u, v, p);
    }
};

pub const Image = struct {
    image: *const RTWImage,

    pub fn value(self: Image, u: f32, v: f32, p: @Vector(3, f32)) @Vector(3, f32) {
        _ = p;

        // If we have no texture data, return solid red as a debugging aid
        if (self.image.height() <= 0) {
            return @Vector(3, f32){ 1, 0, 0 };
        }

        // Clamp input texture coordinates to [0,1] x [1,0]
        const clamped_u = clamp(u, 0.0, 1.0);
        const clamped_v = 1.0 - clamp(v, 0.0, 1.0); // Flip V to image coordinates

        const i = @as(i32, @intFromFloat(clamped_u * @as(f32, @floatFromInt(self.image.width()))));
        const j = @as(i32, @intFromFloat(clamped_v * @as(f32, @floatFromInt(self.image.height()))));

        const pixel = self.image.pixelData(i, j);

        const color_scale = 1.0 / 255.0;
        return @Vector(3, f32){
            color_scale * @as(f32, @floatFromInt(pixel[0])),
            color_scale * @as(f32, @floatFromInt(pixel[1])),
            color_scale * @as(f32, @floatFromInt(pixel[2])),
        };
    }

    fn clamp(x: f32, min: f32, max: f32) f32 {
        if (x < min) return min;
        if (x > max) return max;
        return x;
    }
};
