const rtw = @import("rtweekend.zig");
const std = @import("std");

pub const Perlin = struct {
    const point_count = 256;

    randfloat: [point_count]f32,
    perm_x: [point_count]u8,
    perm_y: [point_count]u8,
    perm_z: [point_count]u8,

    pub fn init() Perlin {
        var randfloat: [point_count]f32 = undefined;
        var perm_x: [point_count]u8 = undefined;
        var perm_y: [point_count]u8 = undefined;
        var perm_z: [point_count]u8 = undefined;

        for (&randfloat) |*f| {
            f.* = rtw.random_double();
        }

        generate_perm(&perm_x);
        generate_perm(&perm_y);
        generate_perm(&perm_z);

        return .{
            .randfloat = randfloat,
            .perm_x = perm_x,
            .perm_y = perm_y,
            .perm_z = perm_z,
        };
    }

    pub fn noise(self: Perlin, p: @Vector(3, f32)) f32 {
        // Calculate floor and fractional parts in one go
        const floored = @floor(p);
        const frac = p - floored;

        // Hermite smoothing
        const u = frac[0] * frac[0] * (3.0 - 2.0 * frac[0]);
        const v = frac[1] * frac[1] * (3.0 - 2.0 * frac[1]);
        const w = frac[2] * frac[2] * (3.0 - 2.0 * frac[2]);

        // Convert to grid indices once
        const i = @as(u8, @truncate(@as(u32, @bitCast(@as(i32, @intFromFloat(floored[0]))))));
        const j = @as(u8, @truncate(@as(u32, @bitCast(@as(i32, @intFromFloat(floored[1]))))));
        const k = @as(u8, @truncate(@as(u32, @bitCast(@as(i32, @intFromFloat(floored[2]))))));

        // Unroll the corner lookups completely - this is much faster than nested loops
        // Pre-compute all indices
        const i_0 = i;
        const i_1 = i +% 1;
        const j0 = j;
        const j1 = j +% 1;
        const k0 = k;
        const k1 = k +% 1;

        // Hash all 8 corners using XOR (matches C++)
        const c000 = self.randfloat[self.perm_x[i_0] ^ self.perm_y[j0] ^ self.perm_z[k0]];
        const c001 = self.randfloat[self.perm_x[i_0] ^ self.perm_y[j0] ^ self.perm_z[k1]];
        const c010 = self.randfloat[self.perm_x[i_0] ^ self.perm_y[j1] ^ self.perm_z[k0]];
        const c011 = self.randfloat[self.perm_x[i_0] ^ self.perm_y[j1] ^ self.perm_z[k1]];
        const c100 = self.randfloat[self.perm_x[i_1] ^ self.perm_y[j0] ^ self.perm_z[k0]];
        const c101 = self.randfloat[self.perm_x[i_1] ^ self.perm_y[j0] ^ self.perm_z[k1]];
        const c110 = self.randfloat[self.perm_x[i_1] ^ self.perm_y[j1] ^ self.perm_z[k0]];
        const c111 = self.randfloat[self.perm_x[i_1] ^ self.perm_y[j1] ^ self.perm_z[k1]];

        // Fast trilinear interpolation - unrolled and optimized
        // Interpolate in x direction first
        const c00 = c000 + u * (c100 - c000);
        const c01 = c001 + u * (c101 - c001);
        const c10 = c010 + u * (c110 - c010);
        const c11 = c011 + u * (c111 - c011);

        // Then y direction
        const c0 = c00 + v * (c10 - c00);
        const c1 = c01 + v * (c11 - c01);

        // Finally z direction
        return c0 + w * (c1 - c0);
    }

    pub fn turb(self: Perlin, p: @Vector(3, f32), depth: u32) f32 {
        var accum: f32 = 0.0;
        var temp_p = p;
        var weight: f32 = 1.0;

        // Unroll small depths for common cases
        if (depth == 7) {
            // Most common case - fully unrolled
            accum += weight * self.noise(temp_p);
            weight *= 0.5;
            temp_p = temp_p * @as(@Vector(3, f32), @splat(2.0));

            accum += weight * self.noise(temp_p);
            weight *= 0.5;
            temp_p = temp_p * @as(@Vector(3, f32), @splat(2.0));

            accum += weight * self.noise(temp_p);
            weight *= 0.5;
            temp_p = temp_p * @as(@Vector(3, f32), @splat(2.0));

            accum += weight * self.noise(temp_p);
            weight *= 0.5;
            temp_p = temp_p * @as(@Vector(3, f32), @splat(2.0));

            accum += weight * self.noise(temp_p);
            weight *= 0.5;
            temp_p = temp_p * @as(@Vector(3, f32), @splat(2.0));

            accum += weight * self.noise(temp_p);
            weight *= 0.5;
            temp_p = temp_p * @as(@Vector(3, f32), @splat(2.0));

            accum += weight * self.noise(temp_p);
        } else {
            // General case for other depths
            for (0..depth) |_| {
                accum += weight * self.noise(temp_p);
                weight *= 0.5;
                temp_p = temp_p * @as(@Vector(3, f32), @splat(2.0));
            }
        }

        return @abs(accum);
    }

    fn generate_perm(p: *[point_count]u8) void {
        for (p, 0..) |*val, i| {
            val.* = @as(u8, @intCast(i));
        }
        permute(p, point_count);
    }

    fn permute(p: *[point_count]u8, n: usize) void {
        var i: usize = n - 1;
        while (i > 0) : (i -= 1) {
            const target = @as(usize, @intCast(rtw.random_int(0, @floatFromInt(i))));

            const tmp = p[i];
            p[i] = p[target];
            p[target] = tmp;
        }
    }
};
