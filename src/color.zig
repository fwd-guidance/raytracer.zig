const rtw = @import("rtweekend.zig");

const std = rtw.std;
const Interval = rtw.interval.Interval;

pub const color: @Vector(3, f32) = undefined;

pub fn linear_to_gamma(linear_component: f32) !f32 {
    if (linear_component > 0) return std.math.sqrt(linear_component) else return 0;
}

pub fn write_color(pixel_color: @Vector(3, f32)) !void {
    const stdout = std.io.getStdOut().writer();

    var r: f32 = pixel_color[0];
    var g: f32 = pixel_color[1];
    var b: f32 = pixel_color[2];

    r = try linear_to_gamma(r);
    g = try linear_to_gamma(g);
    b = try linear_to_gamma(b);

    const intensity: Interval = Interval{ .min = 0.000, .max = 0.999 };
    const rbyte: i64 = @as(i64, @intFromFloat(256 * intensity.clamp(r)));
    const gbyte: i64 = @as(i64, @intFromFloat(256 * intensity.clamp(g)));
    const bbyte: i64 = @as(i64, @intFromFloat(256 * intensity.clamp(b)));

    try stdout.print("{d} {d} {d}\n", .{ rbyte, gbyte, bbyte });
}
