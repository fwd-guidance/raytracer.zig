const vec = @import("vec.zig");
const init = @import("vec.vec.init");
const color = @import("color.zig");

const std = @import("std");

pub fn draw_ppm() !void {
    const stdout = std.io.getStdOut().writer();
    // Image

    const image_width: i64 = 256;
    const image_height: i64 = 256;

    // Render

    try stdout.print("P3\n{d} {d} \n255\n", .{ image_width, image_height });

    for (0..image_height) |j| {
        std.debug.print("\rScanlines remaining: {d}\n", .{image_height - @as(i64, @intCast(j))});
        for (0..image_width) |i| {
            const pixel_color = color.color.init(@as(f64, @floatFromInt(i)) / (image_width - 1), @as(f64, @floatFromInt(j)) / (image_height - 1), 0);
            try color.write_color(pixel_color);
            //const stdout = std.io.getStdOut().writer();
            //try stdout.print("{d} {d} {d}\n", .{ ir, ig, ib });
        }
    }

    std.debug.print("\rDone.              \n", .{});
}

pub fn main() !void {
    try draw_ppm();
}
