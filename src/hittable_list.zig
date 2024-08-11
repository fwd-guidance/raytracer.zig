const rtw = @import("rtweekend.zig");

const Interval = rtw.interval.Interval;
const std = rtw.std;
const Ray = rtw.ray.Ray;
const hit_record = rtw.hittable.hit_record;
const Sphere = rtw.sphere.sphere;
const Material = rtw.material.Material;
const ArrayList = std.ArrayList;

pub const Result = struct {
    ok: bool,
    normal: @Vector(3, f64),
    p: @Vector(3, f64),
    mat: *const Material,
};

pub const HittableList = struct {
    objects: ArrayList(Sphere),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .objects = ArrayList(Sphere).init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.*.objects.deinit();
    }

    pub fn add(self: *Self, _sphere: Sphere) anyerror!*Self {
        try self.*.objects.append(_sphere);
        return self;
    }

    pub fn hit(self: Self, r: Ray, ray_t: Interval, rec: *hit_record) bool {
        var temp_rec: hit_record = undefined;
        var hit_anything: bool = false;
        var closest_so_far = ray_t.max;

        for (self.objects.items) |object| {
            if (object.hit(@constCast(&r), Interval{ .min = ray_t.min, .max = closest_so_far }, @constCast(&temp_rec))) {
                hit_anything = true;
                closest_so_far = temp_rec.t;
                rec.* = temp_rec;
            }
        }
        return hit_anything;
        //return Result{ .ok = hit_anything, .normal = rec.*.normal, .p = rec.*.p, .mat = rec.mat };
    }
};
