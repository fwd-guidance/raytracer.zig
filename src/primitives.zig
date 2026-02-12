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
const HitRecord = scene.HitRecord;

pub const Primitive = union(enum) {
    Sphere: Sphere,
    Quad: Quad,
    Box: Box,
    ConstantMedium: ConstantMedium,

    pub fn hit(self: Primitive, r: *const Ray, ray_t: Interval, rec: *HitRecord) bool {
        switch (self) {
            .Sphere => |s| return s.hit(r, ray_t, rec),
            .Quad => |q| return q.hit(r, ray_t, rec),
            .Box => |b| return b.hit(r, ray_t, rec),
            .ConstantMedium => |cm| return cm.hit(r, ray_t, rec),
        }
    }

    pub fn bounding_box(self: Primitive) AABB {
        switch (self) {
            .Sphere => |s| return s.bounding_box(),
            .Quad => |q| return q.bounding_box(),
            .Box => |b| return b.bounding_box(),
            .ConstantMedium => |cm| return cm.bounding_box(),
        }
    }

    pub fn translate(self: Primitive, offset: @Vector(3, f32)) void {
        switch (self) {
            .Sphere => |s| return s.translate(offset),
            .Quad => |q| return q.translate(offset),
            .Box => |b| return b.translate(offset),
            .ConstantMedium => |cm| return cm.translate(offset),
        }
    }

    pub fn rotate_y(self: Primitive, angle: f32) void {
        switch (self) {
            .Sphere => |s| return s.rotate_y(angle),
            .Quad => |q| return q.rotate_y(angle),
            .Box => |b| return b.rotate_y(angle),
            .ConstantMedium => |cm| return cm.rotate_y(angle),
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
        var bbox = AABB.init_from_points(center - radius_vec, center + radius_vec);
        var center_ray = Ray.init(center, math.init(0, 0, 0), null);

        if (center_two != null) {
            center_ray = Ray.init(center, center_two.? - center, null);
            const box1 = AABB.init_from_points(center_ray.position(0) - radius_vec, center_ray.position(0) + radius_vec);
            const box2 = AABB.init_from_points(center_ray.position(1) - radius_vec, center_ray.position(1) + radius_vec);
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
        const box1 = AABB.init_from_points(center.position(0) - radius_vec, center.position(0) + radius_vec);
        const box2 = AABB.init_from_points(center.position(1) - radius_vec, center.position(1) + radius_vec);
        const bbox = AABB.merge(box1, box2);
        return bbox;
    }

    pub fn hit(self: Self, r: *const Ray, ray_t: Interval, rec: *HitRecord) bool {
        // NOTE: a little sus of this "optimization" of hoisting field accesses. feels like something the compiler would handle itself
        const ray_origin = r.origin;
        const ray_dir = r.direction;

        const current_center = self.center.position(r.tm);

        const oc = current_center - ray_origin;
        const a: f32 = math.square_magnitude(ray_dir);
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

    pub fn get_sphere_uv(p: @Vector(3, f32), rec: *HitRecord) void {
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
            const box1 = AABB.init_from_points(self.center.origin - r_vec, self.center.origin + r_vec);
            const box2 = AABB.init_from_points(self.center.position(1.0) - r_vec, self.center.position(1.0) + r_vec);
            return AABB.merge(box1, box2);
        } else {
            // For static spheres
            return AABB.init_from_points(self.center.origin - r_vec, self.center.origin + r_vec);
        }
    }

    pub fn translate(self: *Sphere, offset: @Vector(3, f32)) void {
        self.center.origin += offset;
        self.bbox.add(offset);
    }

    pub fn rotate_y(self: *Self, angle: f32) void {
        const radians = std.math.degreesToRadians(angle);
        const sin_theta = @sin(radians);
        const cos_theta = @cos(radians);

        // Rotate center around origin
        const old_origin = self.center.origin;
        self.center.origin = @Vector(3, f32){
            cos_theta * old_origin[0] + sin_theta * old_origin[2],
            old_origin[1],
            -sin_theta * old_origin[0] + cos_theta * old_origin[2],
        };

        // If moving sphere, rotate the direction vector too
        if (self.moving) {
            const old_dir = self.center.direction;
            self.center.direction = @Vector(3, f32){
                cos_theta * old_dir[0] + sin_theta * old_dir[2],
                old_dir[1],
                -sin_theta * old_dir[0] + cos_theta * old_dir[2],
            };
        }

        // Recompute bounding box
        self.bbox = self.bounding_box();
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
        const bbox_diagonal1 = AABB.init_from_points(Q, Q + u + v);
        const bbox_diagonal2 = AABB.init_from_points(Q + u, Q + v);
        return AABB.merge(bbox_diagonal1, bbox_diagonal2);
    }

    pub fn bounding_box(self: Quad) AABB {
        return self.bbox;
    }

    pub fn hit(self: Quad, r: *const Ray, ray_t: Interval, rec: *HitRecord) bool {
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

    pub fn is_interior(a: f32, b: f32, rec: *HitRecord) bool {
        const unit_interval = Interval.init(0, 1);

        if (!unit_interval.contains(a) or !unit_interval.contains(b)) return false;

        rec.*.u = a;
        rec.*.v = b;

        return true;
    }

    pub fn translate(self: *Quad, offset: @Vector(3, f32)) void {
        self.Q += offset;
        self.D = math.dot(self.normal, self.Q);
        self.bbox = self.bbox.add(offset);
    }

    pub fn rotate_y(self: *Quad, angle: f32) void {
        const radians = std.math.degreesToRadians(angle);
        const sin_theta = @sin(radians);
        const cos_theta = @cos(radians);

        // Rotate Q, u, v vectors
        self.Q = rotate_y_vec(self.Q, cos_theta, sin_theta);
        self.u = rotate_y_vec(self.u, cos_theta, sin_theta);
        self.v = rotate_y_vec(self.v, cos_theta, sin_theta);

        // Recompute derived values
        const n = math.cross(self.u, self.v);
        self.normal = math.unit(n);
        self.w = n / @as(@Vector(3, f32), @splat(math.dot(n, n)));
        self.D = math.dot(self.normal, self.Q);

        // Recompute bounding box
        self.bbox = set_bounding_box(self.Q, self.u, self.v);
    }

    fn rotate_y_vec(vec: @Vector(3, f32), cos_theta: f32, sin_theta: f32) @Vector(3, f32) {
        return @Vector(3, f32){
            cos_theta * vec[0] + sin_theta * vec[2],
            vec[1],
            -sin_theta * vec[0] + cos_theta * vec[2],
        };
    }
};

pub const Box = struct {
    quads: [6]Quad,
    bbox: AABB,

    const Self = @This();

    pub fn init(a: @Vector(3, f32), b: @Vector(3, f32), mat_id: usize) !Self {
        const min = @Vector(3, f32){ @min(a[0], b[0]), @min(a[1], b[1]), @min(a[2], b[2]) };
        const max = @Vector(3, f32){ @max(a[0], b[0]), @max(a[1], b[1]), @max(a[2], b[2]) };

        const dx = @Vector(3, f32){ max[0] - min[0], 0, 0 };
        const dy = @Vector(3, f32){ 0, max[1] - min[1], 0 };
        const dz = @Vector(3, f32){ 0, 0, max[2] - min[2] };

        var quads: [6]Quad = undefined;

        quads[0] = Quad.init(math.init(min[0], min[1], max[2]), dx, dy, mat_id);
        quads[1] = Quad.init(math.init(max[0], min[1], max[2]), -dz, dy, mat_id);
        quads[2] = Quad.init(math.init(max[0], min[1], min[2]), -dx, dy, mat_id);
        quads[3] = Quad.init(math.init(min[0], min[1], min[2]), dz, dy, mat_id);
        quads[4] = Quad.init(math.init(min[0], max[1], max[2]), dx, -dz, mat_id);
        quads[5] = Quad.init(math.init(min[0], min[1], min[2]), dx, dz, mat_id);

        return Self{
            .quads = quads,
            .bbox = AABB.init_from_points(min, max),
        };
    }

    pub fn hit(self: Self, r: *const Ray, ray_t: Interval, rec: *HitRecord) bool {
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

    pub fn translate(self: *Self, offset: @Vector(3, f32)) void {
        for (&self.quads) |*quad| {
            quad.translate(offset);
        }
        self.bbox = self.bbox.add(offset);
    }

    pub fn rotate_y(self: *Self, angle: f32) void {
        const radians = std.math.degreesToRadians(angle);
        const sin_theta = @sin(radians);
        const cos_theta = @cos(radians);

        for (&self.quads) |*quad| {
            quad.rotate_y(angle);
        }

        // Recompute bounding box by testing all 8 corners
        const old_bbox = self.bbox;
        var min = @Vector(3, f32){ std.math.inf(f32), std.math.inf(f32), std.math.inf(f32) };
        var max = @Vector(3, f32){ -std.math.inf(f32), -std.math.inf(f32), -std.math.inf(f32) };

        for (0..2) |i| {
            for (0..2) |j| {
                for (0..2) |k| {
                    const fi: f32 = @floatFromInt(i);
                    const fj: f32 = @floatFromInt(j);
                    const fk: f32 = @floatFromInt(k);

                    const x = fi * old_bbox.x.max + (1.0 - fi) * old_bbox.x.min;
                    const y = fj * old_bbox.y.max + (1.0 - fj) * old_bbox.y.min;
                    const z = fk * old_bbox.z.max + (1.0 - fk) * old_bbox.z.min;

                    const new_x = cos_theta * x + sin_theta * z;
                    const new_z = -sin_theta * x + cos_theta * z;

                    const tester = @Vector(3, f32){ new_x, y, new_z };

                    min[0] = @min(min[0], tester[0]);
                    min[1] = @min(min[1], tester[1]);
                    min[2] = @min(min[2], tester[2]);

                    max[0] = @max(max[0], tester[0]);
                    max[1] = @max(max[1], tester[1]);
                    max[2] = @max(max[2], tester[2]);
                }
            }
        }

        self.bbox = AABB.init_from_points(min, max);
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
        self.allocator.destroy(self.boundary);
    }

    pub fn hit(self: ConstantMedium, r: *const Ray, ray_t: Interval, rec: *HitRecord) bool {
        var rec1: HitRecord = undefined;
        var rec2: HitRecord = undefined;

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
        return self.boundary.bounding_box();
    }

    pub fn translate(self: *ConstantMedium, offset: @Vector(3, f32)) void {
        self.boundary.translate(offset);
    }

    pub fn rotate_y(self: *ConstantMedium, angle: f32) void {
        self.boundary.rotate_y(angle);
    }
};
