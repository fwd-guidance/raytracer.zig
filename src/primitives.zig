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

    pub fn hit(self: *const Primitive, r: *const Ray, ray_t: Interval, rec: *HitRecord) bool {
        switch (self.*) {
            .Sphere => |*s| return s.hit(r, ray_t, rec),
            .Quad => |*q| return q.hit(r, ray_t, rec),
            .Box => |*b| return b.hit(r, ray_t, rec),
            .ConstantMedium => |*cm| return cm.hit(r, ray_t, rec),
        }
    }

    pub fn bounding_box(self: *const Primitive) *const AABB {
        return switch (self.*) {
            .Sphere => |*s| s.bounding_box(),
            .Quad => |*q| q.bounding_box(),
            .Box => |*b| b.bounding_box(),
            .ConstantMedium => |*cm| cm.bounding_box(),
        };
    }

    pub fn translate(self: *Primitive, offset: @Vector(3, f32)) void {
        switch (self.*) {
            .Sphere => |*s| return s.translate(offset),
            .Quad => |*q| return q.translate(offset),
            .Box => |*b| return b.translate(offset),
            .ConstantMedium => |*cm| return cm.translate(offset),
        }
    }

    pub fn rotate_y(self: *Primitive, angle: f32) void {
        switch (self.*) {
            .Sphere => |*s| return s.rotate_y(angle),
            .Quad => |*q| return q.rotate_y(angle),
            .Box => |*b| return b.rotate_y(angle),
            .ConstantMedium => |*cm| return cm.rotate_y(angle),
        }
    }

    pub fn pdf_value(self: *const Primitive, origin: @Vector(3, f32), direction: @Vector(3, f32)) f32 {
        switch (self.*) {
            .Sphere => |*s| return s.pdf_value(origin, direction),
            .Quad => |*q| return q.pdf_value(origin, direction),
            .Box => |*b| return b.pdf_value(origin, direction),
            .ConstantMedium => |*cm| return cm.pdf_value(origin, direction),
        }
    }

    pub fn random(self: *const Primitive, origin: @Vector(3, f32)) @Vector(3, f32) {
        switch (self.*) {
            .Sphere => |*s| return s.random(origin),
            .Quad => |*q| return q.random(origin),
            .Box => |*b| return b.random(origin),
            .ConstantMedium => |*cm| return cm.random(origin),
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

    pub fn init(center: @Vector(3, f32), center_two: ?@Vector(3, f32), radius: f32, mat_id: usize) Sphere {
        const radius_vec = math.init(radius, radius, radius);
        var bbox = AABB.init_from_points(center - radius_vec, center + radius_vec);
        var center_ray = Ray.init(center, math.init(0, 0, 0), null);

        if (center_two != null) {
            center_ray = Ray.init(center, center_two.? - center, null);
            const box1 = AABB.init_from_points(center_ray.position(0) - radius_vec, center_ray.position(0) + radius_vec);
            const box2 = AABB.init_from_points(center_ray.position(1) - radius_vec, center_ray.position(1) + radius_vec);
            bbox = AABB.merge(box1, box2);
        }

        return .{
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

    pub fn hit(self: *const Sphere, r: *const Ray, ray_t: Interval, rec: *HitRecord) bool {
        const current_center = self.center.position(r.tm);

        const oc = current_center - r.origin;
        const a: f32 = math.square_magnitude(r.direction);
        const h: f32 = math.dot(r.direction, oc);
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

        rec.t = root;

        rec.p = r.position(root);
        const outward_normal: @Vector(3, f32) = (rec.p - current_center) * math.vec3s(self.inv_radius);
        rec.set_face_normal(r, &outward_normal);

        // TODO:
        get_sphere_uv(outward_normal, rec);

        rec.mat_id = self.mat_id;

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

    /// Minimal ray/sphere test used by pdf_value: no HitRecord, no UVs,
    /// no face-normal bookkeeping.
    inline fn intersects(self: *const Sphere, origin: @Vector(3, f32), direction: @Vector(3, f32), t_min: f32, t_max: f32) bool {
        @setFloatMode(.optimized);
        const current_center = self.center.position(0);
        const oc = current_center - origin;
        const a: f32 = math.square_magnitude(direction);
        const h: f32 = math.dot(direction, oc);
        const c: f32 = math.square_magnitude(oc) - self.radius_squared;

        const discriminant: f32 = h * h - a * c;
        if (discriminant < 0) return false;

        const sqrt_discriminant = @sqrt(discriminant);
        const inv_a = 1.0 / a;

        var root: f32 = (h - sqrt_discriminant) * inv_a;
        if (root <= t_min or root >= t_max) {
            root = (h + sqrt_discriminant) * inv_a;
            if (root <= t_min or root >= t_max) return false;
        }
        return true;
    }

    pub fn bounding_box(self: *const Sphere) *const AABB {
        return &self.bbox;
        //const r_vec = @Vector(3, f32){ self.radius, self.radius, self.radius };

        //if (self.moving) {
        //    // For moving spheres, create bounding box that encompasses both positions
        //    const box1 = AABB.init_from_points(self.center.origin - r_vec, self.center.origin + r_vec);
        //    const box2 = AABB.init_from_points(self.center.position(1.0) - r_vec, self.center.position(1.0) + r_vec);
        //    return AABB.merge(box1, box2);
        //} else {
        //    // For static spheres
        //    return AABB.init_from_points(self.center.origin - r_vec, self.center.origin + r_vec);
        //}
    }

    pub fn translate(self: *Sphere, offset: @Vector(3, f32)) void {
        self.center.origin += offset;
        self.bbox = self.bbox.add(offset);
    }

    pub fn rotate_y(self: *Sphere, angle: f32) void {
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
        //self.bbox = self.bounding_box();
        const radius_vec = math.vec3s(self.radius);
        const box1 = AABB.init_from_points(self.center.position(0) - radius_vec, self.center.position(0) + radius_vec);
        if (self.moving) {
            const box2 = AABB.init_from_points(self.center.position(1) - radius_vec, self.center.position(1) + radius_vec);
            self.bbox = AABB.merge(box1, box2);
        } else {
            self.bbox = box1;
        }
    }

    pub fn pdf_value(self: *const Sphere, origin: @Vector(3, f32), direction: @Vector(3, f32)) f32 {
        // Lean intersection test only; skip building a full HitRecord.
        if (!self.intersects(origin, direction, 0.001, std.math.inf(f32))) return 0;

        //var rec: HitRecord = undefined;
        //if (!self.hit(&Ray.init(origin, direction, null), Interval.init(0.001, std.math.inf(f32)), &rec)) return 0;

        const dist_squared = math.square_magnitude(self.center.position(0) - origin);
        const cos_theta_max = @sqrt(1 - self.radius_squared / dist_squared);
        const solid_angle = 2 * std.math.pi * (1 - cos_theta_max);
        return 1.0 / solid_angle;
    }

    pub fn random(self: Sphere, origin: @Vector(3, f32)) @Vector(3, f32) {
        const direction = self.center.position(0) - origin;
        const distance_squared = math.square_magnitude(direction);
        const onb = math.OrthonormalBasis.init(direction);
        return onb.transform(random_to_sphere(self.radius_squared, distance_squared));
    }

    fn random_to_sphere(radius_squared: f32, distance_squared: f32) @Vector(3, f32) {
        const r1 = utils.random_double();
        const r2 = utils.random_double();
        const z = 1 + r2 * (@sqrt(1 - radius_squared / distance_squared) - 1);

        const phi = 2 * std.math.pi * r1;
        const x = @cos(phi) * @sqrt(1 - z * z);
        const y = @sin(phi) * @sqrt(1 - z * z);

        return .{ x, y, z };
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

    u_perp: @Vector(3, f32),
    v_perp: @Vector(3, f32),
    u_perp_q: f32,
    v_perp_q: f32,
    area: f32,

    pub fn init(Q: @Vector(3, f32), u: @Vector(3, f32), v: @Vector(3, f32), mat_id: usize) Quad {
        const n = math.cross(u, v);
        const normal = math.unit(n);

        const w = n / math.vec3s(math.dot(n, n));
        const u_perp = math.cross(v, w);
        const v_perp = math.cross(w, u);
        return .{
            .Q = Q,
            .u = u,
            .v = v,
            .w = w,
            .normal = normal,
            .D = math.dot(normal, Q),
            .mat_id = mat_id,
            .bbox = set_bounding_box(Q, u, v),
            .u_perp = u_perp,
            .v_perp = v_perp,
            .u_perp_q = math.dot(u_perp, Q),
            .v_perp_q = math.dot(v_perp, Q),
            .area = math.magnitude(n),
        };
    }

    pub fn set_bounding_box(Q: @Vector(3, f32), u: @Vector(3, f32), v: @Vector(3, f32)) AABB {
        const bbox_diagonal1 = AABB.init_from_points(Q, Q + u + v);
        const bbox_diagonal2 = AABB.init_from_points(Q + u, Q + v);
        return AABB.merge(bbox_diagonal1, bbox_diagonal2);
    }

    pub fn bounding_box(self: *const Quad) *const AABB {
        return &self.bbox;
    }

    pub fn hit(self: *const Quad, r: *const Ray, ray_t: Interval, rec: *HitRecord) bool {
        const denom = math.dot(self.normal, r.direction);

        // 1. Parallel Check (unchanged)
        if (@abs(denom) < 1e-8) return false;

        // 2. Plane Intersection 't'
        const t = (self.D - math.dot(self.normal, r.origin)) / denom;

        // OPTIMIZATION: Inline the interval check to avoid function call overhead
        if (t < ray_t.min or t > ray_t.max) return false;

        const intersection = r.position(t);
        //const planar_hitpoint_vec = intersection - self.Q;

        // OPTIMIZATION: Check Alpha FIRST
        // If alpha is bad, we return immediately and skip the Beta calculation.
        //const alpha = math.dot(self.w, math.cross(planar_hitpoint_vec, self.v));
        const alpha = math.dot(self.u_perp, intersection) - self.u_perp_q;
        if (alpha < 0 or alpha > 1) return false;

        // OPTIMIZATION: Check Beta SECOND
        //const beta = math.dot(self.w, math.cross(self.u, planar_hitpoint_vec));
        const beta = math.dot(self.v_perp, intersection) - self.v_perp_q;
        if (beta < 0 or beta > 1) return false;

        // If we got here, it's a valid hit.
        rec.t = t;
        rec.p = intersection;
        rec.mat_id = self.mat_id;
        rec.set_face_normal(r, &self.normal);
        rec.u = alpha;
        rec.v = beta;

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
        self.w = n / math.vec3s(math.dot(n, n));
        self.D = math.dot(self.normal, self.Q);

        self.u_perp = math.cross(self.v, self.w);
        self.v_perp = math.cross(self.w, self.u);
        self.u_perp_q = math.dot(self.u_perp, self.Q);
        self.v_perp_q = math.dot(self.v_perp, self.Q);
        self.area = math.magnitude(n);

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

    pub fn pdf_value(self: *const Quad, origin: @Vector(3, f32), direction: @Vector(3, f32)) f32 {

        // Lean intersection test (no HitRecord).
        const denom = math.dot(self.normal, direction);
        if (@abs(denom) < 1e-8) return 0;

        const t = (self.D - math.dot(self.normal, origin)) / denom;
        if (t < 0.001) return 0;

        const intersection = origin + direction * math.vec3s(t);

        const alpha = math.dot(self.u_perp, intersection) - self.u_perp_q;
        const beta = math.dot(self.v_perp, intersection) - self.v_perp_q;
        if (alpha < 0 or alpha > 1 or beta < 0 or beta > 1) return 0;

        const distance_squared = t * t * math.square_magnitude(direction);
        const cosine = @abs(math.dot(direction, self.normal)) / math.magnitude(direction);

        return distance_squared / (cosine * self.area);
    }

    //pub fn pdf_value(self: *const Quad, origin: @Vector(3, f32), direction: @Vector(3, f32)) f32 {
    //    var rec: HitRecord = undefined;
    //    if (!self.hit(&Ray.init(origin, direction, null), Interval.init(0.001, std.math.inf(f32)), &rec)) {
    //        return 0;
    //    }

    //    const distance_squared = rec.t * rec.t * math.square_magnitude(direction);
    //    const cosine = @abs(math.dot(direction, rec.normal) / math.magnitude(direction));

    //    return distance_squared / (cosine * self.area);
    //}

    pub fn random(self: *const Quad, origin: @Vector(3, f32)) @Vector(3, f32) {
        const p = self.Q + (math.scale(self.u, utils.random_double())) + (math.scale(self.v, utils.random_double()));
        return p - origin;
    }
};

pub const Box = struct {
    bbox: AABB, // World-space bounding box (for BVH)
    center: @Vector(3, f32),
    half_size: @Vector(3, f32),
    mat_id: usize,

    // Rotation Cache
    sin_theta: f32,
    cos_theta: f32,

    pub fn init(a: @Vector(3, f32), b: @Vector(3, f32), mat_id: usize) !Box {
        const min = @Vector(3, f32){ @min(a[0], b[0]), @min(a[1], b[1]), @min(a[2], b[2]) };
        const max = @Vector(3, f32){ @max(a[0], b[0]), @max(a[1], b[1]), @max(a[2], b[2]) };

        const center = (min + max) * math.vec3s(0.5);
        const half_size = (max - min) * math.vec3s(0.5);

        return .{
            .bbox = AABB.init_from_points(min, max),
            .center = center,
            .half_size = half_size,
            .mat_id = mat_id,
            .sin_theta = 0.0,
            .cos_theta = 1.0,
        };
    }

    pub fn hit(self: *const Box, r: *const Ray, ray_t: Interval, rec: *HitRecord) bool {
        // 1. Translate Ray to Box Local Space
        // (Treat the box center as 0,0,0)
        const origin_diff = r.origin - self.center;

        // 2. Rotate Ray into Box Alignment (Inverse Rotation)
        // Rotating the ray by -angle is faster than rotating the box geometry.
        // x' = x cos(θ) - z sin(θ)   (standard rotation)
        // x' = x cos(-θ) - z sin(-θ) = x cos(θ) + z sin(θ) (inverse)
        const local_origin = @Vector(3, f32){
            self.cos_theta * origin_diff[0] - self.sin_theta * origin_diff[2],
            origin_diff[1],
            self.sin_theta * origin_diff[0] + self.cos_theta * origin_diff[2],
        };

        const local_dir = @Vector(3, f32){
            self.cos_theta * r.direction[0] - self.sin_theta * r.direction[2],
            r.direction[1],
            self.sin_theta * r.direction[0] + self.cos_theta * r.direction[2],
        };

        // 3. Slab Method Intersection (AABB Logic)
        // We intersect the ray against the box defined by [-half_size, +half_size]

        // Precompute inverse direction for speed (handle div by zero safely or use big number)
        // Note: Zig's vectors handle 1.0/0.0 as Inf, which works with @min/@max logic usually.
        const inv_d = math.vec3s(1.0) / local_dir;

        const t0 = (-self.half_size - local_origin) * inv_d;
        const t1 = (self.half_size - local_origin) * inv_d;

        const t_smaller = @min(t0, t1);
        const t_bigger = @max(t0, t1);

        // Find the largest entry time and smallest exit time
        const t_min = @max(ray_t.min, @reduce(.Max, t_smaller));
        const t_max = @min(ray_t.max, @reduce(.Min, t_bigger));

        if (t_min >= t_max) return false;

        // 4. Hit Calculation
        rec.t = t_min;
        rec.p = r.position(t_min);
        rec.mat_id = self.mat_id;

        // 5. Normal Calculation (Local Space)
        // We figure out which face we hit by seeing which component of t_min matched.
        // A robust way is to check the impact point relative to the box edges.
        // However, since we computed t0/t1 per axis, we know exactly which axis was the entry.

        var local_normal = @Vector(3, f32){ 0, 0, 0 };
        // Determine which axis was the "entry" axis (the Max of the t_smaller values)
        // Note: This creates a tiny branch, but it's predictable.
        if (t_smaller[0] > t_smaller[1] and t_smaller[0] > t_smaller[2]) {
            local_normal[0] = if (local_dir[0] < 0) 1 else -1;
        } else if (t_smaller[1] > t_smaller[2]) {
            local_normal[1] = if (local_dir[1] < 0) 1 else -1;
        } else {
            local_normal[2] = if (local_dir[2] < 0) 1 else -1;
        }

        // 6. Rotate Normal back to World Space
        rec.normal = @Vector(3, f32){
            self.cos_theta * local_normal[0] + self.sin_theta * local_normal[2],
            local_normal[1],
            -self.sin_theta * local_normal[0] + self.cos_theta * local_normal[2],
        };

        rec.front_face = math.dot(r.direction, rec.normal) < 0;
        // 7. Calculate UVs (Optional)
        // Map the hit point on the face to 0..1
        // const local_hit = local_origin + local_dir * @as(@Vector(3, f32), @splat(t_min));
        rec.u = 0;
        rec.v = 0;

        return true;
    }

    pub fn bounding_box(self: *const Box) *const AABB {
        return &self.bbox;
    }

    pub fn translate(self: *Box, offset: @Vector(3, f32)) void {
        self.center += offset;
        self.bbox = self.bbox.add(offset);
    }

    pub fn rotate_y(self: *Box, angle: f32) void {
        const radians = std.math.degreesToRadians(angle);
        const sin_t = @sin(radians);
        const cos_t = @cos(radians);

        // Update cached rotation (accumulation)
        // NOTE: If you only ever rotate from the base state, just overwrite.
        // If you chain rotations, you need to combine the matrices.
        // Assuming simple absolute rotation or single step for Cornell box:
        self.sin_theta = sin_t;
        self.cos_theta = cos_t;

        // Rotate Center
        const old_origin = self.center;
        // (Assuming rotation is around the WORLD origin, not object center, per your Sphere/Quad code)
        self.center = @Vector(3, f32){
            cos_t * old_origin[0] + sin_t * old_origin[2],
            old_origin[1],
            -sin_t * old_origin[0] + cos_t * old_origin[2],
        };

        // Recompute World AABB (Axis-Aligned Bounding Box of the OBB)
        // We check all 8 corners of the OBB in world space.
        var min = @Vector(3, f32){ std.math.inf(f32), std.math.inf(f32), std.math.inf(f32) };
        var max = @Vector(3, f32){ -std.math.inf(f32), -std.math.inf(f32), -std.math.inf(f32) };

        // Loop 8 corners: (+-x, +-y, +-z) relative to center, then rotated
        for (0..2) |i| {
            for (0..2) |j| {
                for (0..2) |k| {
                    // Sign: 0 -> -1, 1 -> +1
                    const sx: f32 = if (i == 0) -1.0 else 1.0;
                    const sy: f32 = if (j == 0) -1.0 else 1.0;
                    const sz: f32 = if (k == 0) -1.0 else 1.0;

                    // Local corner unrotated
                    const local_corner = self.half_size * @Vector(3, f32){ sx, sy, sz };

                    // Rotate corner
                    const rot_corner = @Vector(3, f32){ cos_t * local_corner[0] + sin_t * local_corner[2], local_corner[1], -sin_t * local_corner[0] + cos_t * local_corner[2] };

                    const world_point = self.center + rot_corner;

                    min = @min(min, world_point);
                    max = @max(max, world_point);
                }
            }
        }
        self.bbox = AABB.init_from_points(min, max);
    }

    pub fn pdf_value(self: *const Box, origin: @Vector(3, f32), direction: @Vector(3, f32)) f32 {
        _ = self;
        _ = origin;
        _ = direction;
        return 0.0;
    }

    pub fn random(self: *const Box, origin: @Vector(3, f32)) @Vector(3, f32) {
        _ = self;
        _ = origin;

        return math.init(1, 0, 0);
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

    pub fn hit(self: *const ConstantMedium, r: *const Ray, ray_t: Interval, rec: *HitRecord) bool {
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

    pub fn bounding_box(self: *const ConstantMedium) *const AABB {
        return self.boundary.bounding_box();
    }

    pub fn translate(self: *ConstantMedium, offset: @Vector(3, f32)) void {
        self.boundary.translate(offset);
    }

    pub fn rotate_y(self: *ConstantMedium, angle: f32) void {
        self.boundary.rotate_y(angle);
    }

    pub fn pdf_value(self: *const ConstantMedium, origin: @Vector(3, f32), direction: @Vector(3, f32)) f32 {
        _ = self;
        _ = origin;
        _ = direction;
        return 0.0;
    }

    pub fn random(self: *const ConstantMedium, origin: @Vector(3, f32)) @Vector(3, f32) {
        _ = self;
        _ = origin;

        return math.init(1, 0, 0);
    }
};
