const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    // Image

    const image_width: i64 = 256;
    const image_height: i64 = 256;

    // Render

    try stdout.print("P3\n{d} {d} \n255\n", .{ image_width, image_height });

    for (0..image_height) |j| {
        std.debug.print("\rScanlines remaining: {d}\n", .{image_height - @as(i64, @intCast(j))});
        for (0..image_width) |i| {
            const r = @as(f64, @floatFromInt(i)) / (image_width - 1);
            const g = @as(f64, @floatFromInt(j)) / (image_height - 1);
            const b = 0.0;

            const ir: i32 = @as(i32, @intFromFloat(255.999 * r));
            const ig: i32 = @as(i32, @intFromFloat(255.999 * g));
            const ib: i32 = @as(i32, @intFromFloat(255.999 * b));

            //const stdout = std.io.getStdOut().writer();
            try stdout.print("{d} {d} {d}\n", .{ ir, ig, ib });
        }
    }

    std.debug.print("\rDone.              \n", .{});
}
