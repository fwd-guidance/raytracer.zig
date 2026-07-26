const std = @import("std");
const math = @import("math.zig");

// ---------------------------------------------------------------------------
// Thread-local PRNG: std.Random.Xoroshiro128
// ---------------------------------------------------------------------------
// We use the stdlib engine but call .next() directly rather than going through
// the .random() / std.Random fat-pointer interface.  That interface routes every
// call through .fill() → byte-swap → int conversion, which roughly doubles the
// cost of a single float (documented in ziglang/zig#10037).  Calling .next()
// and doing our own 24-bit extraction keeps the hot path to ~4 instructions.
//
// Why Xoroshiro128 and not our previous hand-rolled Xoshiro256**?
//   • The engine body is identical quality for Monte-Carlo work.  Both pass
//     BigCrush; the period difference (2^128-1 vs 2^256-1) is irrelevant here.
//   • Xoroshiro128 state is 16 bytes vs 32 — half the TLS footprint per thread,
//     though the absolute saving is small (256 bytes across 16 threads).  The
//     real win is that we delete ~30 lines of hand-written PRNG and hand off
//     correctness and the zero-state guard to a well-tested stdlib type.
//   • Seeding drops from "fill 32 bytes from crypto.random + all-zero check"
//     down to "get one u64 from crypto.random".  Xoroshiro128.init() internally
//     expands that single seed through SplitMix64 to fill both state words,
//     which already guarantees a non-zero state.
// ---------------------------------------------------------------------------

const ThreadLocal = struct {
    threadlocal var prng: std.Random.Xoroshiro128 = undefined;
    threadlocal var seeded: bool = false;
};

/// Lazy one-time seed per thread.  Reads a single u64 from the OS CSPRNG;
/// Xoroshiro128.init() expands it via SplitMix64 internally.
inline fn ensure_seeded() void {
    if (!ThreadLocal.seeded) {
        @branchHint(.cold);
        set_seed();
    }
}

fn set_seed() void {
    var seed: u64 = undefined;

    // Leaf-code entropy fetch: no Io handle is threaded through this
    // codebase, so spin up a throwaway single-threaded Io just to pull
    // one seed from the OS CSPRNG. Cheap since this only runs once per thread.
    var io_threaded: std.Io.Threaded = .init_single_threaded;
    defer io_threaded.deinit();
    const io = io_threaded.io();

    io.random(std.mem.asBytes(&seed));

    ThreadLocal.prng = std.Random.Xoroshiro128.init(seed);
    ThreadLocal.seeded = true;
}

/// Returns a uniformly distributed f32 in [0, 1).
///
/// We call .next() directly on the engine — not .random().float() — to avoid
/// the std.Random interface overhead.  The conversion mirrors what the
/// interface does internally anyway: take the top 24 bits (f32 mantissa width)
/// and divide by 2^24.
pub inline fn random_double() f32 {
    ensure_seeded();
    return @as(f32, @floatFromInt(ThreadLocal.prng.next() >> 40)) * (1.0 / 16777216.0);
}

pub inline fn random_double_range(min: f32, max: f32) f32 {
    return min + (max - min) * random_double();
}

pub inline fn random_int(min: f32, max: f32) i64 {
    return @intFromFloat(random_double_range(min, max + 1));
}

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
            f.* = random_double();
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

    pub fn noise(self: *const Perlin, p: @Vector(3, f32)) f32 {
        // Calculate floor and fractional parts in one go
        const floored = @floor(p);
        const frac = p - floored;

        // Hermite smoothing
        const u = frac[0] * frac[0] * (3.0 - 2.0 * frac[0]);
        const v = frac[1] * frac[1] * (3.0 - 2.0 * frac[1]);
        const w = frac[2] * frac[2] * (3.0 - 2.0 * frac[2]);

        // Convert to grid indices once
        const i = math.floorToU8(floored[0]);
        const j = math.floorToU8(floored[1]);
        const k = math.floorToU8(floored[2]);

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

    pub fn turb(self: *const Perlin, p: @Vector(3, f32), depth: u32) f32 {
        var accum: f32 = 0.0;
        var temp_p = p;
        var weight: f32 = 1.0;

        // Unroll small depths for common cases
        if (depth == 7) {
            // Most common case - fully unrolled
            accum += weight * self.noise(temp_p);
            weight *= 0.5;
            temp_p = temp_p * math.vec3s(2.0);

            accum += weight * self.noise(temp_p);
            weight *= 0.5;
            temp_p = temp_p * math.vec3s(2.0);

            accum += weight * self.noise(temp_p);
            weight *= 0.5;
            temp_p = temp_p * math.vec3s(2.0);

            accum += weight * self.noise(temp_p);
            weight *= 0.5;
            temp_p = temp_p * math.vec3s(2.0);

            accum += weight * self.noise(temp_p);
            weight *= 0.5;
            temp_p = temp_p * math.vec3s(2.0);

            accum += weight * self.noise(temp_p);
            weight *= 0.5;
            temp_p = temp_p * math.vec3s(2.0);

            accum += weight * self.noise(temp_p);
        } else {
            // General case for other depths
            for (0..depth) |_| {
                accum += weight * self.noise(temp_p);
                weight *= 0.5;
                temp_p = temp_p * math.vec3s(2.0);
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
            const target = @as(usize, @intCast(random_int(0, @floatFromInt(i))));

            const tmp = p[i];
            p[i] = p[target];
            p[target] = tmp;
        }
    }
};

const c = @import("c");

const red = [_]u8{ 255, 0, 0 };

pub const RTWImage = struct {
    fdata: ?[*]f32 = null,
    bdata: ?[]u8 = null,
    image_width: i32 = 0,
    image_height: i32 = 0,
    bytes_per_pixel: i32 = 3,
    bytes_per_scanline: i32 = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RTWImage {
        return .{ .allocator = allocator };
    }

    pub fn init_from_file(allocator: std.mem.Allocator, image_filename: []const u8) !RTWImage {
        var self = RTWImage.init(allocator);

        if (std.c.getenv("RTW_IMAGES")) |imagedir| {
            const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ imagedir, image_filename });
            defer allocator.free(full_path);
            if (self.load(full_path)) {
                return self;
            }
        }

        // Hunt for the image file in likely locations
        const search_paths = [_][]const u8{
            "",
            "images/",
            "../images/",
            "../../images/",
            "../../../images/",
            "../../../../images/",
            "../../../../../images/",
            "../../../../../../images/",
        };

        for (search_paths) |prefix| {
            const full_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, image_filename });
            defer allocator.free(full_path);
            if (self.load(full_path)) {
                return self;
            }
        }

        std.debug.print("ERROR: Could not load image file '{s}'.\n", .{image_filename});
        return self;
    }
    pub fn deinit(self: *RTWImage) void {
        if (self.bdata) |data| {
            self.allocator.free(data);
            self.bdata = null;
        }
        if (self.fdata) |data| {
            c.stbi_image_free(data);
            self.fdata = null;
        }
    }

    fn load(self: *RTWImage, filename: []const u8) bool {
        // Need null-terminated string for C
        const filename_z = self.allocator.dupeSentinel(u8, filename, 0) catch return false;
        defer self.allocator.free(filename_z);

        var n: i32 = 0; // Dummy out parameter: original components per pixel
        self.fdata = c.stbi_loadf(
            filename_z.ptr,
            &self.image_width,
            &self.image_height,
            &n,
            self.bytes_per_pixel,
        );

        if (self.fdata == null) return false;

        self.bytes_per_scanline = self.image_width * self.bytes_per_pixel;
        self.convert_to_bytes() catch return false;
        return true;
    }

    pub fn width(self: *const RTWImage) i32 {
        return if (self.fdata == null) 0 else self.image_width;
    }

    pub fn height(self: *const RTWImage) i32 {
        return if (self.fdata == null) 0 else self.image_height;
    }

    pub fn pixel_data(self: *const RTWImage, x: i32, y: i32) [*]const u8 {
        // Return the address of the three RGB bytes of the pixel at x,y.
        // If there is no image data, returns red.
        if (self.bdata == null) return &red;

        const clamped_x = clamp(x, 0, self.image_width);
        const clamped_y = clamp(y, 0, self.image_height);

        const offset = @as(usize, @intCast(clamped_y * self.bytes_per_scanline + clamped_x * self.bytes_per_pixel));
        return self.bdata.?[offset..].ptr;
    }

    fn clamp(x: i32, low: i32, high: i32) i32 {
        // Return the value clamped to the range [low, high).
        if (x < low) return low;
        if (x < high) return x;
        return high - 1;
    }

    fn float_to_byte(value: f32) u8 {
        if (value <= 0.0) return 0;
        if (value >= 1.0) return 255;
        return @intFromFloat(256.0 * value);
    }

    fn convert_to_bytes(self: *RTWImage) !void {
        // Convert the linear floating point pixel data to bytes
        const total_bytes = @as(usize, @intCast(self.image_width * self.image_height * self.bytes_per_pixel));

        const byte_data = try self.allocator.alloc(u8, total_bytes);

        // Iterate through all pixel components, converting from [0.0, 1.0] float values
        // to unsigned [0, 255] byte values
        var i: usize = 0;
        while (i < total_bytes) : (i += 1) {
            byte_data[i] = float_to_byte(self.fdata.?[i]);
        }

        self.bdata = byte_data;
    }
};
