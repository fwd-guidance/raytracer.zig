const std = @import("std");
const mlx = @import("mlx");

test "generated module exposes types and matching function signatures" {
    try std.testing.expect(@hasDecl(mlx, "array"));
    try std.testing.expect(@hasDecl(mlx, "dtype"));
    try std.testing.expect(@hasDecl(mlx, "FLOAT32"));
    try std.testing.expect(!@hasDecl(mlx, "mlx_array"));
    try std.testing.expect(@typeInfo(@TypeOf(mlx.array_new)).@"fn".return_type.? == mlx.array);
    try std.testing.expect(@typeInfo(@TypeOf(mlx.string_new)).@"fn".return_type.? == mlx.string);
    try std.testing.expect(@TypeOf(mlx.array_empty) == *mlx.array);
}

test "unsupported C declarations stay lazy" {
    try std.testing.expect(@hasDecl(mlx, "complex64_t"));
    try std.testing.expect(@hasDecl(mlx, "array_item_complex64"));
    try std.testing.expect(@hasDecl(mlx, "array_data_bfloat16"));
    try std.testing.expect(@hasDecl(mlx, "error"));
}
