@vs vs
in vec4 position;
in vec4 color0;

out vec4 color;

void main() {
    gl_Position = position;
    color = position;
}
@end

@fs fs
in vec4 color;
out vec4 frag_color;

// Define constants
#define MAX_SPHERES 500 // Maximum number of spheres
#define MAX_BVH_NODES 1000 // Maximum number of BVH nodes
#define MAX_DEPTH 51
#define EPSILON 0.001
#define INFINITY_F 1.0e20
#define PI 3.1415926535897932385

// Material types
#define LAMBERTIAN 0
#define METAL 1
#define DIELECTRIC 2

// Use vec4 arrays for uniform blocks as required by sokol
layout(binding=0) uniform fs_params {
    vec4 u_params;              // x: samples_per_pixel, y: max_depth, z: aspect_ratio, w: vfov
    vec4 u_camera_params;       // x: defocus_angle, y: focus_dist, z: sphere_count, w: bvh_node_count
    vec4 u_lookfrom;            // xyz: lookfrom, w: unused
    vec4 u_lookat;              // xyz: lookat, w: unused
    vec4 u_vup;                 // xyz: vup, w: unused
    vec4 u_resolution;          // xy: resolution, zw: unused
    
    // Sphere data stored in vec4 arrays
    vec4 u_sphere_data_1[MAX_SPHERES]; // center(xyz), radius(w)
    vec4 u_sphere_data_2[MAX_SPHERES]; // material_type(x), albedo(yzw)
    vec4 u_sphere_data_3[MAX_SPHERES]; // metal_fuzz(x), refraction_index(y), unused(zw)
    
    // BVH node data
    vec4 u_bvh_nodes_min[MAX_BVH_NODES];   // min bounds (xyz), left_index (w)
    vec4 u_bvh_nodes_max[MAX_BVH_NODES];   // max bounds (xyz), right_index (w)
    vec4 u_bvh_nodes_info[MAX_BVH_NODES];  // item_index (x), is_leaf (y), unused (zw)
};

// Camera variables
vec3 camera_center;
vec3 pixel00_loc;
vec3 pixel_delta_u;
vec3 pixel_delta_v;
vec3 u, v, w;
vec3 defocus_disk_u;
vec3 defocus_disk_v;

// Random state
uint seed;

// Ray structure
struct Ray {
    vec3 origin;
    vec3 direction;
};

// Hit record structure
struct HitRecord {
    vec3 p;
    vec3 normal;
    float t;
    bool front_face;
    int material_type;
    vec3 albedo;
    float metal_fuzz;
    float refraction_index;
};

// Material handling
struct ScatterResult {
    bool is_scattered;
    vec3 attenuation;
    Ray scattered_ray;
};

// Interval structure (equivalent to Zig's Interval)
struct Interval {
    float min;
    float max;
};

// AABB structure (equivalent to Zig's AABB)
struct AABB {
    Interval x;
    Interval y;
    Interval z;
};

// Create an empty interval
Interval empty_interval() {
    return Interval(INFINITY_F, -INFINITY_F);
}

// Create a universal interval
Interval universe_interval() {
    return Interval(-INFINITY_F, INFINITY_F);
}

// Get interval size
float interval_size(Interval interval) {
    return interval.max - interval.min;
}

// Check if interval contains a value
bool interval_contains(Interval interval, float value) {
    return interval.min <= value && value <= interval.max;
}

// Check if interval surrounds a value
bool interval_surrounds(Interval interval, float value) {
    return interval.min < value && value < interval.max;
}

// Clamp a value to interval
float interval_clamp(Interval interval, float value) {
    if (value < interval.min) return interval.min;
    if (value > interval.max) return interval.max;
    return value;
}

// Expand an interval by a delta amount
Interval interval_expand(Interval interval, float delta) {
    float padding = delta / 2.0;
    return Interval(interval.min - padding, interval.max + padding);
}

// Merge two intervals
Interval interval_merge(Interval a, Interval b) {
    return Interval(min(a.min, b.min), max(a.max, b.max));
}

// Create an empty AABB
AABB empty_aabb() {
    Interval empty = empty_interval();
    return AABB(empty, empty, empty);
}

// Create AABB from two points
AABB aabb_from_points(vec3 a, vec3 b) {
    return AABB(
        Interval(min(a.x, b.x), max(a.x, b.x)),
        Interval(min(a.y, b.y), max(a.y, b.y)),
        Interval(min(a.z, b.z), max(a.z, b.z))
    );
}

// Pad an AABB
AABB aabb_pad(AABB box) {
    float delta = 0.0001;
    Interval new_x = (interval_size(box.x) >= delta) ? box.x : interval_expand(box.x, delta);
    Interval new_y = (interval_size(box.y) >= delta) ? box.y : interval_expand(box.y, delta);
    Interval new_z = (interval_size(box.z) >= delta) ? box.z : interval_expand(box.z, delta);
    
    return AABB(new_x, new_y, new_z);
}

// Merge two AABBs
AABB aabb_merge(AABB a, AABB b) {
    return AABB(
        interval_merge(a.x, b.x),
        interval_merge(a.y, b.y),
        interval_merge(a.z, b.z)
    );
}

// Check if ray hits AABB
bool aabb_hit(AABB box, Ray r, Interval ray_t) {
    float t_min = ray_t.min;
    float t_max = ray_t.max;
    
    // X axis
    float invD = 1.0 / r.direction.x;
    float t0 = (box.x.min - r.origin.x) * invD;
    float t1 = (box.x.max - r.origin.x) * invD;
    
    if (invD < 0.0) {
        float temp = t0;
        t0 = t1;
        t1 = temp;
    }
    
    t_min = max(t0, t_min);
    t_max = min(t1, t_max);
    
    if (t_max <= t_min) return false;
    
    // Y axis
    invD = 1.0 / r.direction.y;
    t0 = (box.y.min - r.origin.y) * invD;
    t1 = (box.y.max - r.origin.y) * invD;
    
    if (invD < 0.0) {
        float temp = t0;
        t0 = t1;
        t1 = temp;
    }
    
    t_min = max(t0, t_min);
    t_max = min(t1, t_max);
    
    if (t_max <= t_min) return false;
    
    // Z axis
    invD = 1.0 / r.direction.z;
    t0 = (box.z.min - r.origin.z) * invD;
    t1 = (box.z.max - r.origin.z) * invD;
    
    if (invD < 0.0) {
        float temp = t0;
        t0 = t1;
        t1 = temp;
    }
    
    t_min = max(t0, t_min);
    t_max = min(t1, t_max);
    
    return t_max > t_min;
}

// Get the AABB for a sphere
AABB get_sphere_box(int sphere_index) {
    vec3 center = u_sphere_data_1[sphere_index].xyz;
    float radius = u_sphere_data_1[sphere_index].w;
    
    vec3 radius_vec = vec3(radius, radius, radius);
    vec3 min_point = center - radius_vec;
    vec3 max_point = center + radius_vec;
    
    return aabb_from_points(min_point, max_point);
}

// Function to hash a uint value
uint wang_hash(uint seed) {
    seed = (seed ^ 61) ^ (seed >> 16);
    seed *= 9;
    seed = seed ^ (seed >> 4);
    seed *= 0x27d4eb2d;
    seed = seed ^ (seed >> 15);
    return seed;
}

// Generate a random float in [0, 1)
float rand() {
    seed = wang_hash(seed);
    return float(seed) / 4294967296.0;
}

// Random float in range [min, max)
float rand_range(float min, float max) {
    return min + (max - min) * rand();
}

// Generate a random vector with components in [0,1)
vec3 random_vec() {
    return vec3(rand(), rand(), rand());
}

// Generate a random vector with components in [min,max)
vec3 random_vec_range(float min, float max) {
    return vec3(rand_range(min, max), rand_range(min, max), rand_range(min, max));
}

// Vector utility functions
bool near_zero(vec3 v) {
    const float s = 1e-8;
    return (abs(v.x) < s) && (abs(v.y) < s) && (abs(v.z) < s);
}

vec3 random_in_unit_sphere() {
    while (true) {
        vec3 p = random_vec_range(-1.0, 1.0);
        if (dot(p, p) < 1.0) return p;
    }
}

vec3 random_unit_vector() {
    return normalize(random_in_unit_sphere());
}

vec3 random_in_unit_disk() {
    while (true) {
        vec3 p = vec3(rand_range(-1.0, 1.0), rand_range(-1.0, 1.0), 0.0);
        if (dot(p, p) < 1.0) return p;
    }
}

vec3 random_on_hemisphere(vec3 normal) {
    vec3 on_unit_sphere = random_unit_vector();
    if (dot(on_unit_sphere, normal) > 0.0) {
        return on_unit_sphere;
    } else {
        return -on_unit_sphere;
    }
}

vec3 custom_reflect(vec3 v, vec3 n) {
    return v - 2.0 * dot(v, n) * n;
}

vec3 custom_refract(vec3 uv, vec3 n, float etai_over_etat) {
    float cos_theta = min(dot(-uv, n), 1.0);
    vec3 r_out_perp = etai_over_etat * (uv + cos_theta * n);
    vec3 r_out_parallel = -sqrt(abs(1.0 - dot(r_out_perp, r_out_perp))) * n;
    return r_out_perp + r_out_parallel;
}

// Schlick approximation for reflectance
float reflectance(float cosine, float ref_idx) {
    float r0 = (1.0 - ref_idx) / (1.0 + ref_idx);
    r0 = r0 * r0;
    return r0 + (1.0 - r0) * pow((1.0 - cosine), 5.0);
}

// Ray position at parameter t
vec3 ray_at(Ray r, float t) {
    return r.origin + t * r.direction;
}

// Calculate camera parameters
void initialize_camera() {
    camera_center = u_lookfrom.xyz;

    // Camera parameters
    float vfov = u_params.w;
    float focus_dist = u_camera_params.y;
    float defocus_angle = u_camera_params.x;
    vec2 resolution = u_resolution.xy;

    // Calculate viewport dimensions
    float theta = radians(vfov);
    float h = tan(theta/2.0);
    float viewport_height = 2.0 * h * focus_dist;
    float viewport_width = viewport_height * (resolution.x / resolution.y);

    // Calculate camera basis vectors
    w = normalize(u_lookfrom.xyz - u_lookat.xyz);
    u = normalize(cross(u_vup.xyz, w));
    v = cross(w, u);

    // Calculate viewport vectors
    vec3 viewport_u = viewport_width * u;
    vec3 viewport_v = viewport_height * -v;

    // Calculate pixel delta vectors
    pixel_delta_u = viewport_u / resolution.x;
    pixel_delta_v = viewport_v / resolution.y;

    // Calculate upper left pixel location
    vec3 viewport_upper_left = camera_center - focus_dist * w - viewport_u/2.0 - viewport_v/2.0;
    pixel00_loc = viewport_upper_left + 0.5 * (pixel_delta_u + pixel_delta_v);
    
    // Calculate defocus disk basis vectors
    float defocus_radius = focus_dist * tan(radians(defocus_angle/2.0));
    defocus_disk_u = u * defocus_radius;
    defocus_disk_v = v * defocus_radius;
}

// Get a ray from the camera to the given pixel (i, j) with defocus blur
Ray get_ray(float i, float j) {
    // Add a random offset to the pixel location for anti-aliasing
    vec3 pixel_sample = pixel00_loc + (i + rand() - 0.5) * pixel_delta_u + (j + rand() - 0.5) * pixel_delta_v;
    
    vec3 ray_origin = camera_center;
    if (u_camera_params.x > 0.0) { // If defocus angle > 0
        vec3 p = random_in_unit_disk();
        ray_origin = camera_center + defocus_disk_u * p.x + defocus_disk_v * p.y;
    }
    
    vec3 ray_direction = pixel_sample - ray_origin;
    
    return Ray(ray_origin, ray_direction);
}

// Set face normal in the hit record
void set_face_normal(inout HitRecord rec, Ray r, vec3 outward_normal) {
    rec.front_face = dot(r.direction, outward_normal) < 0.0;
    rec.normal = rec.front_face ? outward_normal : -outward_normal;
}

// Check if ray hits a sphere
bool hit_sphere(Ray r, float t_min, float t_max, int sphere_index, inout HitRecord rec) {
    vec3 center = u_sphere_data_1[sphere_index].xyz;
    float radius = u_sphere_data_1[sphere_index].w;
    
    vec3 oc = r.origin - center;
    float a = dot(r.direction, r.direction);
    float half_b = dot(oc, r.direction);
    float c = dot(oc, oc) - radius * radius;
    
    float discriminant = half_b * half_b - a * c;
    
    if (discriminant < 0.0) return false;
    
    float sqrtd = sqrt(discriminant);
    
    // Find the nearest root that lies in the acceptable range
    float root = (-half_b - sqrtd) / a;
    if (root < t_min || root > t_max) {
        root = (-half_b + sqrtd) / a;
        if (root < t_min || root > t_max)
            return false;
    }
    
    rec.t = root;
    rec.p = ray_at(r, root);
    vec3 outward_normal = (rec.p - center) / radius;
    set_face_normal(rec, r, outward_normal);
    
    // Set material properties
    rec.material_type = int(u_sphere_data_2[sphere_index].x);
    rec.albedo = u_sphere_data_2[sphere_index].yzw;
    rec.metal_fuzz = u_sphere_data_3[sphere_index].x;
    rec.refraction_index = u_sphere_data_3[sphere_index].y;
    
    return true;
}

// Hit BVH structure recursively
bool hit_bvh(Ray r, float t_min, float t_max, inout HitRecord rec) {
    int stack[64];  // Stack for iterative traversal
    int stack_ptr = 0;
    
    stack[stack_ptr++] = 0;  // Start with root node (index 0)
    
    bool hit_anything = false;
    float closest_so_far = t_max;
    int bvh_node_count = int(u_camera_params.w);
    
    while (stack_ptr > 0) {
        int node_idx = stack[--stack_ptr];
        
        // Skip if node doesn't exist
        if (node_idx < 0 || node_idx >= bvh_node_count) {
            continue;
        }
        
        // Create an AABB for this node
        vec3 box_min = u_bvh_nodes_min[node_idx].xyz;
        vec3 box_max = u_bvh_nodes_max[node_idx].xyz;
        AABB node_box = AABB(
            Interval(box_min.x, box_max.x),
            Interval(box_min.y, box_max.y),
            Interval(box_min.z, box_max.z)
        );
        
        // Skip this node if ray doesn't hit its bounding box
        if (!aabb_hit(node_box, r, Interval(t_min, closest_so_far))) {
            continue;
        }
        
        float is_leaf = u_bvh_nodes_info[node_idx].y;
        
        if (is_leaf > 0.5) {
            // Leaf node - test against sphere
            int sphere_idx = int(u_bvh_nodes_info[node_idx].x);
            HitRecord temp_rec;
            
            if (hit_sphere(r, t_min, closest_so_far, sphere_idx, temp_rec)) {
                hit_anything = true;
                closest_so_far = temp_rec.t;
                rec = temp_rec;
            }
        } else {
            // Internal node - add children to stack
            int right_idx = int(u_bvh_nodes_max[node_idx].w);
            int left_idx = int(u_bvh_nodes_min[node_idx].w);
            
            // Push right child first (so left is processed first)
            stack[stack_ptr++] = right_idx;
            stack[stack_ptr++] = left_idx;
        }
    }
    
    return hit_anything;
}

// Traditional linear search through spheres
bool hit_spheres_linear(Ray r, float t_min, float t_max, inout HitRecord rec) {
    bool hit_anything = false;
    float closest_so_far = t_max;
    int sphere_count = int(u_camera_params.z);
    
    for (int i = 0; i < MAX_SPHERES; i++) {
        if (i >= sphere_count) break;
        
        HitRecord temp_rec;
        if (hit_sphere(r, t_min, closest_so_far, i, temp_rec)) {
            hit_anything = true;
            closest_so_far = temp_rec.t;
            rec = temp_rec;
        }
    }
    
    return hit_anything;
}

// Check if ray hits any object in the world
bool hit_world(Ray r, float t_min, float t_max, inout HitRecord rec) {
    int bvh_node_count = int(u_camera_params.w);
    
    // Use BVH if available, otherwise fall back to linear search
    if (bvh_node_count > 0) {
        return hit_bvh(r, t_min, t_max, rec);
    } else {
        return hit_spheres_linear(r, t_min, t_max, rec);
    }
}

// Lambertian material scatter function
bool scatter_lambertian(Ray r_in, HitRecord rec, inout vec3 attenuation, inout Ray scattered) {
    vec3 scatter_direction = rec.normal + random_unit_vector();
    
    // Catch degenerate scatter direction
    if (near_zero(scatter_direction))
        scatter_direction = rec.normal;
    
    scattered = Ray(rec.p, scatter_direction);
    attenuation = rec.albedo;
    return true;
}

// Metal material scatter function
bool scatter_metal(Ray r_in, HitRecord rec, inout vec3 attenuation, inout Ray scattered) {
    vec3 reflected = custom_reflect(normalize(r_in.direction), rec.normal);
    scattered = Ray(rec.p, reflected + rec.metal_fuzz * random_in_unit_sphere());
    attenuation = rec.albedo;
    return (dot(scattered.direction, rec.normal) > 0.0);
}

// Dielectric material scatter function
bool scatter_dielectric(Ray r_in, HitRecord rec, inout vec3 attenuation, inout Ray scattered) {
    attenuation = vec3(1.0);
    float refraction_ratio = rec.front_face ? (1.0 / rec.refraction_index) : rec.refraction_index;
    
    vec3 unit_direction = normalize(r_in.direction);
    float cos_theta = min(dot(-unit_direction, rec.normal), 1.0);
    float sin_theta = sqrt(1.0 - cos_theta * cos_theta);
    
    bool cannot_refract = refraction_ratio * sin_theta > 1.0;
    vec3 direction;
    
    if (cannot_refract || reflectance(cos_theta, refraction_ratio) > rand())
        direction = custom_reflect(unit_direction, rec.normal);
    else
        direction = custom_refract(unit_direction, rec.normal, refraction_ratio);
    
    scattered = Ray(rec.p, direction);
    return true;
}

// Dispatch to the appropriate scatter function based on material type
bool scatter(Ray r_in, HitRecord rec, inout vec3 attenuation, inout Ray scattered) {
    if (rec.material_type == LAMBERTIAN) {
        return scatter_lambertian(r_in, rec, attenuation, scattered);
    } else if (rec.material_type == METAL) {
        return scatter_metal(r_in, rec, attenuation, scattered);
    } else if (rec.material_type == DIELECTRIC) {
        return scatter_dielectric(r_in, rec, attenuation, scattered);
    }
    return false;
}

// Ray color function that handles multiple bounces and materials
vec3 ray_color(Ray r, int depth) {
    vec3 color_accum = vec3(1.0);
    Ray current_ray = r;
    
    for (int i = 0; i < MAX_DEPTH; i++) {
        if (i >= depth) break;
        
        HitRecord rec;
        if (hit_world(current_ray, EPSILON, INFINITY_F, rec)) {
            Ray scattered;
            vec3 attenuation;
            
            if (scatter(current_ray, rec, attenuation, scattered)) {
                color_accum *= attenuation;
                current_ray = scattered;
            } else {
                return vec3(0.0); // Absorbed
            }
        } else {
            // Background - sky gradient
            vec3 unit_direction = normalize(current_ray.direction);
            float t = 0.5 * (unit_direction.y + 1.0);
            vec3 sky_color = (1.0 - t) * vec3(1.0) + t * vec3(0.5, 0.7, 1.0);
            return color_accum * sky_color;
        }
    }
    
    // If we've exceeded the bounce limit, return black
    return vec3(0.0);
}

void main() {
    // Initialize random seed based on pixel position
    seed = uint(gl_FragCoord.x * 1973.0 + gl_FragCoord.y * 9277.0 + 26699.0);

    initialize_camera();

    float samples_per_pixel = u_params.x;
    float max_depth = u_params.y;
    
    vec3 pixel_color = vec3(0.0);
    
    // Multi-sample anti-aliasing
    for (float s = 0.0; s < samples_per_pixel; s++) {
        Ray r = get_ray(gl_FragCoord.x, gl_FragCoord.y);
        pixel_color += ray_color(r, int(max_depth));
    }
    
    // Divide by the number of samples and gamma-correct for gamma=2.0
    pixel_color = pixel_color / samples_per_pixel;
    pixel_color = sqrt(pixel_color); // Gamma correction
    
    frag_color = vec4(pixel_color, 1.0);
}
@end

@program render vs fs