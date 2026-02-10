const std = @import("std");
const math = @import("math.zig");
const spatial = @import("spatial.zig");
const scene = @import("scene.zig");
const utils = @import("utils.zig");
const Material = @import("material.zig").Material;

const Ray = math.Ray;
const Interval = math.Interval;
const AABB = spatial.AABB;
const HittableList = scene.HittableList;
const hit_record = scene.hit_record;

pub const Primitive = union(enum) {
    Sphere: Sphere,
    Quad: Quad,
    Box: Box,
    Translate: Translate,
    RotateY: RotateY,
    ConstantMedium: ConstantMedium,

    pub fn hit(self: Primitive, r: *const Ray, ray_t: Interval, rec: *hit_record) bool {
        switch (self) {
            .Sphere => |s| return s.hit(r, ray_t, rec),
            .Quad => |q| return q.hit(r, ray_t, rec),
            .Box => |b| return b.hit(r, ray_t, rec),
            .Translate => |t| return t.hit(r, ray_t, rec),
            .RotateY => |rY| return rY.hit(r, ray_t, rec),
            .ConstantMedium => |cm| return cm.hit(r, ray_t, rec),
        }
    }

    pub fn boundingBox(self: Primitive) AABB {
        switch (self) {
            .Sphere => |s| return s.bounding_box(),
            .Quad => |q| return q.bounding_box(),
            .Box => |b| return b.bounding_box(),
            .Translate => |t| return t.bounding_box(),
            .RotateY => |rY| return rY.bounding_box(),
            .ConstantMedium => |cm| return cm.bounding_box(),
        }
    }
};

pub const Sphere = struct {
    center: Ray,
    radius: f32,
    inv_radius: f32,
    radius_squared: f32,
    mat_id: usize,
    moving: bool,
    bbox: AABB,

    const Self = @This();

    pub fn init(center: @Vector(3, f32), center_two: ?@Vector(3, f32), radius: f32, mat_id: usize) Self {
        const radius_vec = math.init(radius, radius, radius);
        var bbox = AABB.fromPoints(center - radius_vec, center + radius_vec);
        var center_ray = Ray.init(center, math.init(0, 0, 0), null);

        if (center_two != null) {
            center_ray = Ray.init(center, center_two.? - center, null);
            const box1 = AABB.fromPoints(center_ray.position(0) - radius_vec, center_ray.position(0) + radius_vec);
            const box2 = AABB.fromPoints(center_ray.position(1) - radius_vec, center_ray.position(1) + radius_vec);
            bbox = AABB.merge(box1, box2);
        }

        return Self{
            .center = center_ray,
            .radius = radius,
            .inv_radius = 1.0 / radius,
            .radius_squared = radius * radius,
            .mat_id = mat_id,
            .moving = center_two != null,
            .bbox = bbox,
        };
    }

    fn init_moving_bbox(center: Ray, radius: f32) AABB {
        const radius_vec = math.init(radius, radius, radius);
        const box1 = AABB.fromPoints(center.position(0) - radius_vec, center.position(0) + radius_vec);
        const box2 = AABB.fromPoints(center.position(1) - radius_vec, center.position(1) + radius_vec);
        const bbox = AABB.merge(box1, box2);
        return bbox;
    }

    pub fn hit(self: Self, r: *const Ray, ray_t: Interval, rec: *hit_record) bool {
        // NOTE: a little sus of this "optimization" of hoisting field accesses. feels like something the compiler would handle itself
        const ray_origin = r.origin;
        const ray_dir = r.direction;

        const current_center = self.center.position(r.tm);

        //const oc: @Vector(3, f32) = self.center - r.*.origin;
        //const oc: @Vector(3, f32) = self.center - ray_origin;
        const oc = current_center - ray_origin;
        //const a: f32 = vec.square_magnitude(r.*.direction);
        const a: f32 = math.square_magnitude(ray_dir);
        //const h: f32 = vec.dot(r.*.direction, oc);
        const h: f32 = math.dot(ray_dir, oc);
        const c: f32 = math.square_magnitude(oc) - self.radius_squared;

        const discriminant: f32 = h * h - a * c;
        if (discriminant < 0) return false;

        const sqrt_discriminant = @sqrt(discriminant);
        const inv_a = 1.0 / a;

        // Find the nearest root that lies in the acceptable range
        var root: f32 = (h - sqrt_discriminant) * inv_a;
        if (!ray_t.surrounds(root)) {
            root = (h + sqrt_discriminant) * inv_a;
            if (!ray_t.surrounds(root)) {
                return false;
            }
        }

        rec.*.t = root;

        rec.*.p = r.position(root);
        const outward_normal: @Vector(3, f32) = (rec.*.p - current_center) * @as(@Vector(3, f32), @splat(self.inv_radius));
        rec.set_face_normal(r, &outward_normal);

        get_sphere_uv(outward_normal, rec);

        rec.*.mat_id = self.mat_id;

        return true;
    }

    pub fn get_sphere_uv(p: @Vector(3, f32), rec: *hit_record) void {
        // TODO: ideally this fn would be able to easily rotate an img by an arbitrary amount from the caller.
        //      like, being able to view any part of the earthmap vs being forced to see the americas.
        const theta = std.math.acos(-p[1]);
        const phi = std.math.atan2(-p[2], p[0]) + std.math.pi;

        rec.*.u = phi / (2 * std.math.pi);

        // rotates the img 90 degrees, which in the earthmap example means that you will see the prime meridian and not the americas.
        //rec.*.u += 0.25;
        //if (rec.*.u > 1.0) rec.*.u -= 1.0;

        rec.*.v = theta / std.math.pi;
    }

    pub fn bounding_box(self: Self) AABB {
        const r_vec = @Vector(3, f32){ self.radius, self.radius, self.radius };

        if (self.moving) {
            // For moving spheres, create bounding box that encompasses both positions
            const box1 = AABB.fromPoints(self.center.origin - r_vec, self.center.origin + r_vec);
            const box2 = AABB.fromPoints(self.center.position(1.0) - r_vec, self.center.position(1.0) + r_vec);
            return AABB.merge(box1, box2);
        } else {
            // For static spheres
            return AABB.fromPoints(self.center.origin - r_vec, self.center.origin + r_vec);
        }
    }
};

pub const Quad = struct {
    Q: @Vector(3, f32),
    u: @Vector(3, f32),
    v: @Vector(3, f32),
    w: @Vector(3, f32),
    normal: @Vector(3, f32),
    D: f32,
    mat_id: usize,
    bbox: AABB,

    pub fn init(Q: @Vector(3, f32), u: @Vector(3, f32), v: @Vector(3, f32), mat_id: usize) Quad {
        const n = math.cross(u, v);
        const normal = math.unit(n);

        return .{
            .Q = Q,
            .u = u,
            .v = v,
            .w = n / @as(@Vector(3, f32), @splat(math.dot(n, n))),
            .normal = normal,
            .D = math.dot(normal, Q),
            .mat_id = mat_id,
            .bbox = set_bounding_box(Q, u, v),
        };
    }

    pub fn set_bounding_box(Q: @Vector(3, f32), u: @Vector(3, f32), v: @Vector(3, f32)) AABB {
        const bbox_diagonal1 = AABB.fromPoints(Q, Q + u + v);
        const bbox_diagonal2 = AABB.fromPoints(Q + u, Q + v);
        return AABB.merge(bbox_diagonal1, bbox_diagonal2);
    }

    pub fn bounding_box(self: Quad) AABB {
        return self.bbox;
    }

    pub fn hit(self: Quad, r: *const Ray, ray_t: Interval, rec: *hit_record) bool {
        const denom = math.dot(self.normal, r.*.direction);
        // bounds check unnecessary?
        if (@abs(denom) < 1e-8) return false;

        const t = (self.D - math.dot(self.normal, r.*.origin)) / denom;
        if (!ray_t.contains(t)) return false;

        const intersection = r.*.position(t);

        const planar_hitpoint_vec = intersection - self.Q;
        const alpha = math.dot(self.w, math.cross(planar_hitpoint_vec, self.v));
        const beta = math.dot(self.w, math.cross(self.u, planar_hitpoint_vec));

        if (!is_interior(alpha, beta, rec)) return false;

        rec.*.t = t;
        rec.*.p = intersection;
        rec.*.mat_id = self.mat_id;
        rec.*.set_face_normal(r, &self.normal);
        return true;
    }

    pub fn is_interior(a: f32, b: f32, rec: *hit_record) bool {
        const unit_interval = Interval.init(0, 1);

        if (!unit_interval.contains(a) or !unit_interval.contains(b)) return false;

        rec.*.u = a;
        rec.*.v = b;

        return true;
    }
};

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
        quads[0].* = .{ .Quad = Quad.init(math.init(min[0], min[1], max[2]), dx, dy, mat_id) };

        quads[1] = try allocator.create(Primitive);
        quads[1].* = .{ .Quad = Quad.init(math.init(max[0], min[1], max[2]), -dz, dy, mat_id) };

        quads[2] = try allocator.create(Primitive);
        quads[2].* = .{ .Quad = Quad.init(math.init(max[0], min[1], min[2]), -dx, dy, mat_id) };

        quads[3] = try allocator.create(Primitive);
        quads[3].* = .{ .Quad = Quad.init(math.init(min[0], min[1], min[2]), dz, dy, mat_id) };

        quads[4] = try allocator.create(Primitive);
        quads[4].* = .{ .Quad = Quad.init(math.init(min[0], max[1], max[2]), dx, -dz, mat_id) };

        quads[5] = try allocator.create(Primitive);
        quads[5].* = .{ .Quad = Quad.init(math.init(min[0], min[1], min[2]), dx, dz, mat_id) };

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

pub const ConstantMedium = struct {
    boundary: *Primitive,
    neg_inv_density: f32,
    phase_function_mat_id: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, boundary: Primitive, density: f32, tex_id: usize, world: *HittableList) !ConstantMedium {
        const boundary_ptr = try allocator.create(Primitive);
        boundary_ptr.* = boundary;

        // Create isotropic material and add to world
        const phase_function = Material.isotropic(tex_id);
        const mat_id = try world.add_material(phase_function);

        return .{
            .boundary = boundary_ptr,
            .neg_inv_density = -1.0 / density,
            .phase_function_mat_id = mat_id,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ConstantMedium) void {
        switch (self.boundary.*) {
            .Translate => |*t| t.deinit(),
            .RotateY => |*r| r.deinit(),
            .Box => |*b| b.deinit(),
            else => {},
        }
        self.allocator.destroy(self.boundary);
    }

    pub fn hit(self: ConstantMedium, r: *const Ray, ray_t: Interval, rec: *hit_record) bool {
        var rec1: hit_record = undefined;
        var rec2: hit_record = undefined;

        // Check if ray hits boundary at all
        if (!self.boundary.hit(r, Interval.universe(), &rec1)) {
            return false;
        }

        // Check if ray hits boundary again (exit point)
        if (!self.boundary.hit(r, Interval.init(rec1.t + 0.0001, std.math.inf(f32)), &rec2)) {
            return false;
        }

        // Clamp to valid ray interval
        if (rec1.t < ray_t.min) rec1.t = ray_t.min;
        if (rec2.t > ray_t.max) rec2.t = ray_t.max;

        if (rec1.t >= rec2.t) {
            return false;
        }

        if (rec1.t < 0) {
            rec1.t = 0;
        }

        const ray_length = math.magnitude(r.direction);
        const distance_inside_boundary = (rec2.t - rec1.t) * ray_length;
        const hit_distance = self.neg_inv_density * @log(utils.random_double());

        if (hit_distance > distance_inside_boundary) {
            return false;
        }

        rec.t = rec1.t + hit_distance / ray_length;
        rec.p = r.position(rec.t);

        rec.normal = @Vector(3, f32){ 1, 0, 0 }; // arbitrary
        rec.front_face = true; // also arbitrary
        rec.mat_id = self.phase_function_mat_id;

        return true;
    }

    pub fn bounding_box(self: ConstantMedium) AABB {
        return self.boundary.boundingBox();
    }
};

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
