const rtw = @import("rtweekend.zig");
const interval = @import("interval.zig");
const Interval = interval.Interval;
const std = rtw.std;
const math = std.math;
const vec = rtw.vec;
const ray = rtw.ray;
const hittable = rtw.hittable;
const sphere = rtw.sphere;
const Sphere = rtw.sphere.sphere;

const ArrayList = std.ArrayList;

pub const Result = struct {
    ok: bool,
    result: @Vector(3, f64),
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

    pub fn hit(self: Self, r: ray.Ray, ray_t: Interval, rec: *hittable.hit_record) Result {
        const temp_rec: hittable.hit_record = undefined;
        var hit_anything: bool = false;
        var closest_so_far = ray_t.max;

        for (self.objects.items) |object| {
            if (object.hit(@constCast(&r), Interval{ .min = ray_t.min, .max = closest_so_far }, @constCast(&temp_rec))) {
                hit_anything = true;
                closest_so_far = temp_rec.t;
                //std.debug.print("temp_rec.t = {}\n", .{temp_rec.t});
                //std.debug.print("hit anything = {}\n", .{hit_anything});
                //std.debug.print("closest_so_far = {}\n", .{closest_so_far});
                //rec.* = temp_rec;
                //std.debug.print("hittable_list rec.*.normal = {}\n", .{rec.*.normal});
            }
        }
        //std.debug.print("HEREHEREHEREHERE: {}\n", .{rec.*.normal});
        return Result{ .ok = hit_anything, .result = rec.*.normal };
    }
};
