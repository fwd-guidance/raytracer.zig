pub const std = @import("std");
const math = std.math;

pub const color = @import("color.zig");

pub const ray = @import("ray.zig");
pub const Ray = ray.Ray;

pub const vec = @import("vec.zig");
pub const init = vec.init;
pub const Vec3 = vec.Vec3;
pub const Point3 = vec.Point3;

pub const hittable = @import("hittable.zig");
pub const hit_record = hittable.hit_record;

pub const sphere = @import("sphere.zig");
pub const Sphere = sphere.sphere;

pub const HittableList = @import("hittable_list.zig");

pub const interval = @import("interval.zig");
pub const Interval = interval.Interval;

pub const camera = @import("camera.zig");
pub const Camera = camera.Camera;

pub const material = @import("material.zig");
pub const Material = material.Material;

pub const aabb = @import("aabb.zig");
pub const AABB = aabb.AABB;

pub const bvh = @import("bvh.zig");
pub const BVHNode = bvh.BVHNode;
pub const Hittable = bvh.Hittable;

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

const thread_local = struct {
    threadlocal var prng: std.Random.Xoroshiro128 = undefined;
    threadlocal var seeded: bool = false;
};

/// Lazy one-time seed per thread.  Reads a single u64 from the OS CSPRNG;
/// Xoroshiro128.init() expands it via SplitMix64 internally.
fn ensureSeeded() void {
    if (!thread_local.seeded) {
        var seed: u64 = undefined;
        std.crypto.random.bytes(@as(*[8]u8, @ptrCast(&seed)));
        thread_local.prng = std.Random.Xoroshiro128.init(seed);
        thread_local.seeded = true;
    }
}

/// Returns a uniformly distributed f32 in [0, 1).
///
/// We call .next() directly on the engine — not .random().float() — to avoid
/// the std.Random interface overhead.  The conversion mirrors what the
/// interface does internally anyway: take the top 24 bits (f32 mantissa width)
/// and divide by 2^24.
pub fn random_double() f32 {
    ensureSeeded();
    return @as(f32, @floatFromInt(thread_local.prng.next() >> 40)) * (1.0 / 16777216.0);
}

pub fn random_double_range(min: f32, max: f32) f32 {
    return min + (max - min) * random_double();
}

pub fn random_int(min: f32, max: f32) i64 {
    return @intFromFloat(random_double_range(min, max + 1));
}
