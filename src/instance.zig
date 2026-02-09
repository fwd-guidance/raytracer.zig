const std = @import("std");
const Primitive = @import("hittable_list.zig").Primitive;
const AABB = @import("aabb.zig").AABB;
const Ray = @import("ray.zig").Ray;
const Interval = @import("interval.zig").Interval;
const hit_record = @import("hittable.zig").hit_record;
const Box = @import("box.zig").Box;

pub const Translate = struct {
    primitive: *Primitive,
    offset: @Vector(3, f32),
    bbox: AABB,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, primitive: Primitive, offset: @Vector(3, f32)) !Translate {
        const obj_ptr = try allocator.create(Primitive);
        obj_ptr.* = primitive;

        const obj_bbox = primitive.boundingBox();
        const bbox = obj_bbox.add(offset);
        return .{
            .primitive = obj_ptr,
            .offset = offset,
            .bbox = bbox,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Translate) void {
        switch (self.primitive.*) {
            .Translate => |*t| t.deinit(),
            .RotateY => |*r| r.deinit(),
            .Box => |*b| b.deinit(),
            else => {},
        }
        self.allocator.destroy(self.primitive);
    }

    pub fn hit(self: Translate, r: *const Ray, ray_t: Interval, rec: *hit_record) bool {
        const offset_r: Ray = Ray.init(r.*.origin - self.offset, r.*.direction, r.*.tm);

        if (!self.primitive.hit(&offset_r, ray_t, rec)) {
            return false;
        }

        rec.*.p += self.offset;

        return true;
    }

    pub fn bounding_box(self: Translate) AABB {
        return self.bbox;
    }
};

pub const RotateY = struct {
    primitive: *Primitive,
    sin_theta: f32,
    cos_theta: f32,
    bbox: AABB,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, primitive: Primitive, angle: f32) !RotateY {
        const obj_ptr = try allocator.create(Primitive);
        obj_ptr.* = primitive;

        const radians = std.math.degreesToRadians(angle);
        const sin_theta = @sin(radians);
        const cos_theta = @cos(radians);

        const prim_bbox = primitive.boundingBox();
        var min = @Vector(3, f32){ std.math.inf(f32), std.math.inf(f32), std.math.inf(f32) };
        var max = @Vector(3, f32){ -std.math.inf(f32), -std.math.inf(f32), -std.math.inf(f32) };

        // Test all 8 corners of the bounding box
        for (0..2) |i| {
            for (0..2) |j| {
                for (0..2) |k| {
                    const fi: f32 = @floatFromInt(i);
                    const fj: f32 = @floatFromInt(j);
                    const fk: f32 = @floatFromInt(k);

                    // Get corner point (interpolate between min and max)
                    const x = fi * prim_bbox.x.max + (1.0 - fi) * prim_bbox.x.min;
                    const y = fj * prim_bbox.y.max + (1.0 - fj) * prim_bbox.y.min;
                    const z = fk * prim_bbox.z.max + (1.0 - fk) * prim_bbox.z.min;

                    // Rotate the corner point
                    const new_x = cos_theta * x + sin_theta * z;
                    const new_z = -sin_theta * x + cos_theta * z;

                    const tester = @Vector(3, f32){ new_x, y, new_z };

                    // Expand bounding box
                    min[0] = @min(min[0], tester[0]);
                    min[1] = @min(min[1], tester[1]);
                    min[2] = @min(min[2], tester[2]);

                    max[0] = @max(max[0], tester[0]);
                    max[1] = @max(max[1], tester[1]);
                    max[2] = @max(max[2], tester[2]);
                }
            }
        }

        const bbox = AABB.fromPoints(min, max);
        return .{
            .primitive = obj_ptr,
            .sin_theta = sin_theta,
            .cos_theta = cos_theta,
            .bbox = bbox,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RotateY) void {
        switch (self.primitive.*) {
            .Translate => |*t| t.deinit(),
            .RotateY => |*r| r.deinit(),
            .Box => |*b| b.deinit(),
            else => {},
        }
        self.allocator.destroy(self.primitive);
    }

    pub fn hit(self: RotateY, r: *const Ray, ray_t: Interval, rec: *hit_record) bool {
        const origin = @Vector(3, f32){ self.cos_theta * r.origin[0] - self.sin_theta * r.origin[2], r.origin[1], self.sin_theta * r.origin[0] + self.cos_theta * r.origin[2] };
        const direction = @Vector(3, f32){ self.cos_theta * r.*.direction[0] - self.sin_theta * r.*.direction[2], r.*.direction[1], self.sin_theta * r.*.direction[0] + self.cos_theta * r.*.direction[2] };

        const rotated_r = Ray.init(origin, direction, r.*.tm);

        if (!self.primitive.hit(&rotated_r, ray_t, rec)) return false;

        rec.*.p = @Vector(3, f32){ self.cos_theta * rec.*.p[0] + self.sin_theta * rec.*.p[2], rec.*.p[1], -self.sin_theta * rec.*.p[0] + self.cos_theta * rec.*.p[2] };
        rec.*.normal = @Vector(3, f32){ self.cos_theta * rec.*.normal[0] + self.sin_theta * rec.*.normal[2], rec.*.normal[1], -self.sin_theta * rec.*.normal[0] + self.cos_theta * rec.*.normal[2] };

        return true;
    }

    pub fn bounding_box(self: RotateY) AABB {
        return self.bbox;
    }
};
