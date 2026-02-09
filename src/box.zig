const Primitive = @import("hittable_list.zig").Primitive;
const std = @import("std");
const AABB = @import("aabb.zig").AABB;
const Quad = @import("quad.zig").Quad;
const vec = @import("vec.zig");
const Ray = @import("ray.zig").Ray;
const Interval = @import("interval.zig").Interval;
const rtw = @import("rtweekend.zig");
const hit_record = rtw.hit_record;

pub const Box = struct {
    quads: [6]*Primitive,
    bbox: AABB,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, a: @Vector(3, f32), b: @Vector(3, f32), mat_id: usize) !Self {
        const min = @Vector(3, f32){ @min(a[0], b[0]), @min(a[1], b[1]), @min(a[2], b[2]) };
        const max = @Vector(3, f32){ @max(a[0], b[0]), @max(a[1], b[1]), @max(a[2], b[2]) };

        const dx = @Vector(3, f32){ max[0] - min[0], 0, 0 };
        const dy = @Vector(3, f32){ 0, max[1] - min[1], 0 };
        const dz = @Vector(3, f32){ 0, 0, max[2] - min[2] };

        var quads: [6]*Primitive = undefined;

        quads[0] = try allocator.create(Primitive);
        quads[0].* = .{ .Quad = Quad.init(vec.init(min[0], min[1], max[2]), dx, dy, mat_id) };

        quads[1] = try allocator.create(Primitive);
        quads[1].* = .{ .Quad = Quad.init(vec.init(max[0], min[1], max[2]), -dz, dy, mat_id) };

        quads[2] = try allocator.create(Primitive);
        quads[2].* = .{ .Quad = Quad.init(vec.init(max[0], min[1], min[2]), -dx, dy, mat_id) };

        quads[3] = try allocator.create(Primitive);
        quads[3].* = .{ .Quad = Quad.init(vec.init(min[0], min[1], min[2]), dz, dy, mat_id) };

        quads[4] = try allocator.create(Primitive);
        quads[4].* = .{ .Quad = Quad.init(vec.init(min[0], max[1], max[2]), dx, -dz, mat_id) };

        quads[5] = try allocator.create(Primitive);
        quads[5].* = .{ .Quad = Quad.init(vec.init(min[0], min[1], min[2]), dx, dz, mat_id) };

        return Self{
            .quads = quads,
            .bbox = AABB.fromPoints(min, max),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.quads) |quad| {
            switch (quad.*) {
                .Translate => |*t| t.deinit(),
                .RotateY => |*r| r.deinit(),
                else => {},
            }
            self.allocator.destroy(quad);
        }
    }

    pub fn hit(self: Self, r: *const Ray, ray_t: Interval, rec: *hit_record) bool {
        var hit_anything = false;
        var closest_so_far = ray_t.max;

        for (self.quads) |quad| {
            if (quad.hit(r, Interval.init(ray_t.min, closest_so_far), rec)) {
                hit_anything = true;
                closest_so_far = rec.t;
            }
        }

        return hit_anything;
    }

    pub fn bounding_box(self: Self) AABB {
        return self.bbox;
    }
};
