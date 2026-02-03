const rtw = @import("rtweekend.zig");
const Interval = rtw.interval.Interval;

pub fn linear_to_gamma(linear_component: f32) f32 {
    if (linear_component > 0) return @sqrt(linear_component) else return 0;
}

inline fn writeU8(writer: anytype, value: u8) !void {
    if (value >= 100) {
        try writer.writeByte('0' + value / 100);
    }
    if (value >= 10) {
        try writer.writeByte('0' + (value / 10) % 10);
    }
    try writer.writeByte('0' + value % 10);
}

pub fn write_color(writer: anytype, pixel_color: @Vector(3, f32)) !void {
    const r: f32 = linear_to_gamma(pixel_color[0]);
    const g: f32 = linear_to_gamma(pixel_color[1]);
    const b: f32 = linear_to_gamma(pixel_color[2]);

    const intensity: Interval = Interval{ .min = 0.000, .max = 0.999 };
    const rbyte = @as(u8, @intFromFloat(256 * intensity.clamp(r)));
    const gbyte = @as(u8, @intFromFloat(256 * intensity.clamp(g)));
    const bbyte = @as(u8, @intFromFloat(256 * intensity.clamp(b)));

    try writeU8(writer, rbyte);
    try writer.writeByte(' ');
    try writeU8(writer, gbyte);
    try writer.writeByte(' ');
    try writeU8(writer, bbyte);
    try writer.writeByte('\n');
}
