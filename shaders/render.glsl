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


struct Sphere {
    vec3 center;
    float radius;
    int material_type;  // 0: Lambertian, 1: Metal, 2: Dielectric
    vec3 albedo;
    float metal_fuzz;
    float refraction_index;
};


layout(binding=0) uniform fs_params {
  vec2 u_resolution;
  int u_samples_per_pixel;  // Number of samples per pixel
  int u_max_depth;  // Maximum ray recursion depth
  float u_aspect_ratio;  // Aspect ratio of the viewport
  vec3 u_lookfrom;  // Camera position
  vec3 u_lookat;  // Point camera is looking at
  vec3 u_vup;  // Camera up vector
  float u_vfov;  // Vertical field of view in degrees
  float u_defocus_angle;  // Camera defocus angle
  float u_focus_dist;  // Focus distance
  int u_sphere_count;
  //Sphere u_spheres[u_sphere_count];
  Sphere u_spheres[500];
};

// #version 330 core

// uniform vec2 u_resolution;  // Screen resolution
// uniform int u_samples_per_pixel;  // Number of samples per pixel
// uniform int u_max_depth;  // Maximum ray recursion depth
// uniform float u_aspect_ratio;  // Aspect ratio of the viewport
// uniform vec3 u_lookfrom;  // Camera position
// uniform vec3 u_lookat;  // Point camera is looking at
// uniform vec3 u_vup;  // Camera up vector
// uniform float u_vfov;  // Vertical field of view in degrees
// uniform float u_defocus_angle;  // Camera defocus angle
// uniform float u_focus_dist;  // Focus distance

// Output color
//out vec4 fragColor;

// Constants
const float INFINITY = 1.0e20;
const float PI = 3.1415926535897932385;
const float EPSILON = 0.001;

// Structures
struct Ray {
    vec3 origin;
    vec3 direction;
};

struct HitRecord {
    vec3 p;
    vec3 normal;
    float t;
    bool front_face;
    int material_type;  // 0: Lambertian, 1: Metal, 2: Dielectric
    vec3 albedo;
    float metal_fuzz;
    float refraction_index;
};

// Replace with uniform arrays in real implementation
// #define MAX_SPHERES 500
// uniform Sphere u_spheres[MAX_SPHERES];
// uniform int u_sphere_count;

// Camera variables
vec3 camera_center;
vec3 pixel00_loc;
vec3 pixel_delta_u;
vec3 pixel_delta_v;
vec3 u, v, w;
vec3 defocus_disk_u;
vec3 defocus_disk_v;

// Random number generation
uint seed = uint(gl_FragCoord.x * 1973.0 + gl_FragCoord.y * 9277.0 + 26699.0);

// Random functions
uint wang_hash(inout uint seed) {
    seed = uint(seed ^ uint(61)) ^ uint(seed >> uint(16));
    seed *= uint(9);
    seed = seed ^ (seed >> 4);
    seed *= uint(0x27d4eb2d);
    seed = seed ^ (seed >> 15);
    return seed;
}

float random_float(inout uint local_seed) {
    return float(wang_hash(local_seed)) / 4294967296.0;
}

float random_float_range(float min, float max, inout uint local_seed) {
    return min + (max - min) * random_float(local_seed);
}

vec3 random_vec(inout uint local_seed) {
    return vec3(
        random_float(local_seed),
        random_float(local_seed),
        random_float(local_seed)
    );
}

vec3 random_vec_range(float min, float max, inout uint local_seed) {
    return vec3(
        random_float_range(min, max, local_seed),
        random_float_range(min, max, local_seed),
        random_float_range(min, max, local_seed)
    );
}

vec3 random_in_unit_disk(inout uint local_seed) {
    while (true) {
        vec3 p = vec3(random_float_range(-1.0, 1.0, local_seed), random_float_range(-1.0, 1.0, local_seed), 0.0);
        if (dot(p, p) < 1.0) return p;
    }
}

vec3 random_in_unit_sphere(inout uint local_seed) {
    while (true) {
        vec3 p = random_vec_range(-1.0, 1.0, local_seed);
        if (dot(p, p) < 1.0) return p;
    }
}

vec3 random_unit_vector(inout uint local_seed) {
    return normalize(random_in_unit_sphere(local_seed));
}

vec3 random_on_hemisphere(vec3 normal, inout uint local_seed) {
    vec3 on_unit_sphere = random_unit_vector(local_seed);
    if (dot(on_unit_sphere, normal) > 0.0)
        return on_unit_sphere;
    else
        return -on_unit_sphere;
}

bool near_zero(vec3 v) {
    return (abs(v.x) < EPSILON) && (abs(v.y) < EPSILON) && (abs(v.z) < EPSILON);
}

vec3 _reflect(vec3 v, vec3 n) {
    return v - 2.0 * dot(v, n) * n;
}

vec3 _refract(vec3 uv, vec3 n, float etai_over_etat) {
    float cos_theta = min(dot(-uv, n), 1.0);
    vec3 r_out_perp = etai_over_etat * (uv + cos_theta * n);
    vec3 r_out_parallel = -sqrt(abs(1.0 - dot(r_out_perp, r_out_perp))) * n;
    return r_out_perp + r_out_parallel;
}

float reflectance(float cosine, float ref_idx) {
    // Use Schlick's approximation for reflectance
    float r0 = (1.0 - ref_idx) / (1.0 + ref_idx);
    r0 = r0 * r0;
    return r0 + (1.0 - r0) * pow((1.0 - cosine), 5.0);
}

void set_face_normal(inout HitRecord rec, Ray r, vec3 outward_normal) {
    rec.front_face = dot(r.direction, outward_normal) < 0.0;
    rec.normal = rec.front_face ? outward_normal : -outward_normal;
}

vec3 ray_at(Ray r, float t) {
    return r.origin + t * r.direction;
}

bool hit_sphere(Sphere sphere, Ray r, float t_min, float t_max, inout HitRecord rec) {
    vec3 oc = r.origin - sphere.center;
    float a = dot(r.direction, r.direction);
    float half_b = dot(oc, r.direction);
    float c = dot(oc, oc) - sphere.radius * sphere.radius;
    
    float discriminant = half_b * half_b - a * c;
    if (discriminant < 0.0) return false;
    
    // Find the nearest root that lies in the acceptable range
    float sqrtd = sqrt(discriminant);
    float root = (-half_b - sqrtd) / a;
    if (root < t_min || t_max < root) {
        root = (-half_b + sqrtd) / a;
        if (root < t_min || t_max < root)
            return false;
    }
    
    rec.t = root;
    rec.p = ray_at(r, root);
    vec3 outward_normal = (rec.p - sphere.center) / sphere.radius;
    set_face_normal(rec, r, outward_normal);
    rec.material_type = sphere.material_type;
    rec.albedo = sphere.albedo;
    rec.metal_fuzz = sphere.metal_fuzz;
    rec.refraction_index = sphere.refraction_index;
    
    return true;
}

bool hit_world(Ray r, float t_min, float t_max, inout HitRecord rec) {
    HitRecord temp_rec;
    bool hit_anything = false;
    float closest_so_far = t_max;
    
    for (int i = 0; i < u_sphere_count; i++) {
        if (hit_sphere(u_spheres[i], r, t_min, closest_so_far, temp_rec)) {
            hit_anything = true;
            closest_so_far = temp_rec.t;
            rec = temp_rec;
        }
    }
    
    return hit_anything;
}

bool scatter(Ray r_in, HitRecord rec, inout vec3 attenuation, inout Ray scattered, inout uint local_seed) {
    if (rec.material_type == 0) {
        // Lambertian material
        vec3 scatter_direction = rec.normal + random_unit_vector(local_seed);
        
        // Catch degenerate scatter direction
        if (near_zero(scatter_direction))
            scatter_direction = rec.normal;
            
        scattered = Ray(rec.p, scatter_direction);
        attenuation = rec.albedo;
        return true;
    } 
    else if (rec.material_type == 1) {
        // Metal material
        vec3 reflected = _reflect(normalize(r_in.direction), rec.normal);
        scattered = Ray(rec.p, reflected + rec.metal_fuzz * random_unit_vector(local_seed));
        attenuation = rec.albedo;
        return (dot(scattered.direction, rec.normal) > 0.0);
    } 
    else if (rec.material_type == 2) {
        // Dielectric material
        attenuation = vec3(1.0, 1.0, 1.0);
        float refraction_ratio = rec.front_face ? (1.0 / rec.refraction_index) : rec.refraction_index;
        
        vec3 unit_direction = normalize(r_in.direction);
        float cos_theta = min(dot(-unit_direction, rec.normal), 1.0);
        float sin_theta = sqrt(1.0 - cos_theta * cos_theta);
        
        bool cannot_refract = refraction_ratio * sin_theta > 1.0;
        vec3 direction;
        
        if (cannot_refract || reflectance(cos_theta, refraction_ratio) > random_float(local_seed))
            direction = _reflect(unit_direction, rec.normal);
        else
            direction = _refract(unit_direction, rec.normal, refraction_ratio);
        
        scattered = Ray(rec.p, direction);
        return true;
    }
    
    return false;
}

vec3 ray_color(Ray r, int depth, inout uint local_seed) {
    HitRecord rec;
    
    // If we've exceeded the ray bounce limit, no more light is gathered
    if (depth <= 0)
        return vec3(0.0, 0.0, 0.0);
    
    // If the ray hits nothing, return the background color (sky)
    if (!hit_world(r, EPSILON, INFINITY, rec)) {
        vec3 unit_direction = normalize(r.direction);
        float a = 0.5 * (unit_direction.y + 1.0);
        return (1.0 - a) * vec3(1.0, 1.0, 1.0) + a * vec3(0.5, 0.7, 1.0);
    }
    
    Ray scattered;
    vec3 attenuation;
    
    if (scatter(r, rec, attenuation, scattered, local_seed))
        return attenuation * ray_color(scattered, depth-1, local_seed);
    
    return vec3(0.0, 0.0, 0.0);
}

vec3 defocus_disk_sample(inout uint local_seed) {
    vec3 p = random_in_unit_disk(local_seed);
    return camera_center + p.x * defocus_disk_u + p.y * defocus_disk_v;
}

Ray get_ray(float i, float j, inout uint local_seed) {
    // Get a randomly sampled camera ray for the pixel at i,j
    
    vec3 offset = vec3(random_float(local_seed) - 0.5, random_float(local_seed) - 0.5, 0.0);
    vec3 pixel_sample = pixel00_loc + (i + offset.x) * pixel_delta_u + (j + offset.y) * pixel_delta_v;
    
    vec3 ray_origin = (u_defocus_angle <= 0.0) ? camera_center : defocus_disk_sample(local_seed);
    vec3 ray_direction = pixel_sample - ray_origin;
    
    return Ray(ray_origin, ray_direction);
}

void initialize_camera() {
    // Camera initialization
    camera_center = u_lookfrom;
    
    // Viewport dimensions
    float theta = radians(u_vfov);
    float h = tan(theta/2.0);
    float viewport_height = 2.0 * h * u_focus_dist;
    float viewport_width = viewport_height * (u_resolution.x / u_resolution.y);
    
    // Camera coordinate system
    w = normalize(u_lookfrom - u_lookat);
    u = normalize(cross(u_vup, w));
    v = cross(w, u);
    
    // Viewport vectors
    vec3 viewport_u = viewport_width * u;
    vec3 viewport_v = viewport_height * -v;
    
    // Calculate the horizontal and vertical delta vectors
    pixel_delta_u = viewport_u / u_resolution.x;
    pixel_delta_v = viewport_v / u_resolution.y;
    
    // Calculate the location of the upper left pixel
    vec3 viewport_upper_left = camera_center - u_focus_dist * w - viewport_u/2.0 - viewport_v/2.0;
    pixel00_loc = viewport_upper_left + 0.5 * (pixel_delta_u + pixel_delta_v);
    
    // Calculate defocus disk basis vectors
    float defocus_radius = u_focus_dist * tan(radians(u_defocus_angle/2.0));
    defocus_disk_u = u * defocus_radius;
    defocus_disk_v = v * defocus_radius;
}

void main() {
    uint local_seed = seed;
    initialize_camera();
    
    vec3 pixel_color = vec3(0.0);
    
    // Sample the pixel multiple times for anti-aliasing
    for (int s = 0; s < u_samples_per_pixel; s++) {
        // Get pixel coordinates
        float i = gl_FragCoord.x;
        float j = u_resolution.y - gl_FragCoord.y; // Flip y coordinate
        
        Ray r = get_ray(i, j, local_seed);
        pixel_color += ray_color(r, u_max_depth, local_seed);
    }
    
    // Average the samples and apply gamma correction
    pixel_color /= float(u_samples_per_pixel);
    pixel_color = sqrt(pixel_color); // Simple gamma correction (gamma 2)
    
    frag_color = vec4(pixel_color, 1.0);
}
@end

@program render vs fs
