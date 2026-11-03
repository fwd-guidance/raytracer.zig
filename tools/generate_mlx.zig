const std = @import("std");
const c = @import("mlx_c");

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &stdout.interface;
    try writer.writeAll("// Generated from the pinned mlx-c headers. Do not edit.\nconst c = @import(\"mlx_c\");\n\n");

    // Read names only: inspecting each declaration's type would eagerly analyze
    // unsupported C declarations that normal Zig imports leave lazy.
    for (@typeInfo(c).@"struct".decl_names) |name| {
        const renamed = strippedName(name) orelse continue;
        // Zig has no variable aliases. Preserve access to this mutable C global
        // through a pointer instead of copying its value into a constant.
        const address = if (std.mem.eql(u8, name, "mlx_array_empty")) "&" else "";
        try writer.print("pub const {f} = {s}c.{f};\n", .{ std.zig.fmtId(renamed), address, std.zig.fmtId(name) });
    }
    try writer.flush();
}

fn strippedName(name: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, name, "mlx") and
        !std.mem.startsWith(u8, name, "MLX_")) return null;
    const suffix = name[3..];
    const result = if (std.mem.startsWith(u8, suffix, "_")) suffix[1..] else suffix;
    return if (result.len == 0) null else result;
}

test "strip MLX prefixes" {
    try std.testing.expectEqualStrings("array", strippedName("mlx_array").?);
    try std.testing.expectEqualStrings("array_new", strippedName("mlx_array_new").?);
    try std.testing.expectEqualStrings("FLOAT32", strippedName("MLX_FLOAT32").?);
    try std.testing.expectEqualStrings("example", strippedName("mlxexample").?);
    try std.testing.expect(strippedName("other") == null);
    try std.testing.expect(strippedName("mlx") == null);
}
