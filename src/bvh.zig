const rtw = @import("rtweekend.zig");
const Ray = rtw.Ray;
const Interval = rtw.Interval;
const hit_record = rtw.hit_record;
const hittable_list = rtw.HittableList.HittableList;
const aabb = rtw.AABB.aabb;

const bvh_node = struct {
    left: bvh_node,
    right: bvh_node,
    bbox: aabb,
    const Self = @This();

    pub fn init(self: *Self, objects: hittable_list, start: i8, end: i8) bvh_node {
        const axis: i64 = rtw.random_int(0, 2);
        const comparator = if (axis == 0) box_x_compare else if (axis == 1) box_y_compare else box_z_compare;

        const object_span: i8 = end - start;

        if (object_span == 1) {
            self.left = objects[start];
            self.right = objects[start];
        } else if (object_span == 2) {
            self.left = objects[start];
            self.right = objects[start + 1];
        } else {
            rtw.std.sort.insertionContext(objects.objects[0 + start] + start, objects.objects[0 + end], comparator);

            const mid: i8 = start + object_span / 2;
            self.left = init(self, objects, start, mid);
            self.right = init(self, objects, mid, end);
        }
        self.bbox = rtw.aabb.aabb_init(self.left.bounding_box(), self.right.bounding_box());
    }

    pub fn hit(self: Self, r: *const Ray, ray_t: Interval, rec: *hit_record) !bool {
        if (!self.bbox.hit(r, ray_t)) return false;

        const hit_left: bool = self.left.hit(r, ray_t, rec);
        const hit_right: bool = self.right.hit(r, Interval{ ray_t.min, if (hit_left) rec.t else ray_t.max }, rec);

        return hit_left or hit_right;
    }

    pub fn bounding_box(self: Self) aabb {
        return self.bbox;
    }

    pub fn box_compare(a: *const bvh_node, b: *const bvh_node, axis_index: i64) bool {
        const a_axis_interval: Interval = a.bounding_box().axis_interval(axis_index);
        const b_axis_interval: Interval = b.bounding_box().axis_interval(axis_index);
        return a_axis_interval.min < b_axis_interval.min;
    }

    pub fn box_x_compare(a: *const bvh_node, b: *const bvh_node) bool {
        return box_compare(a, b, 0);
    }

    pub fn box_y_compare(a: *const bvh_node, b: *const bvh_node) bool {
        return box_compare(a, b, 1);
    }

    pub fn box_z_compare(a: *const bvh_node, b: *const bvh_node) bool {
        return box_compare(a, b, 2);
    }
};
