const vec = @import("vec.zig");
const std = @import("std");
const interval = @import("interval.zig");
const Interval = interval.Interval;

pub const color: @Vector(3, f64) = undefined;

pub fn write_color(pixel_color: @Vector(3, f64)) !void {
    const stdout = std.io.getStdOut().writer();

    const r: f64 = pixel_color[0];
    const g: f64 = pixel_color[1];
    const b: f64 = pixel_color[2];

    const intensity: Interval = Interval{ .min = 0.000, .max = 0.999 };
    const rbyte: i64 = @as(i64, @intFromFloat(256 * intensity.clamp(r)));
    const gbyte: i64 = @as(i64, @intFromFloat(256 * intensity.clamp(g)));
    const bbyte: i64 = @as(i64, @intFromFloat(256 * intensity.clamp(b)));
    //const rbyte: i64 = @as(i64, @intFromFloat(255.999 * r));
    //const gbyte: i64 = @as(i64, @intFromFloat(255.999 * g));
    //const bbyte: i64 = @as(i64, @intFromFloat(255.999 * b));

    try stdout.print("{d} {d} {d}\n", .{ rbyte, gbyte, bbyte });
}
