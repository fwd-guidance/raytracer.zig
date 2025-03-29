// Type definitions for GPU structures
struct Camera {
    center: vec3f,
    pixel00_loc: vec3f,
    pixel_delta_u: vec3f,
    pixel_delta_v: vec3f,
    defocus_disk_u: vec3f,
    defocus_disk_v: vec3f,
    defocus_angle: f32,
    u: vec3f,
    v: vec3f,
    w: vec3f,
    samples_per_pixel: f32,
    max_depth: f32,
    aspect_ratio: f32,
    image_width: f32,
    image_height: f32,
    focus_dist: f32,
}

struct MaterialType {
    material_type: u32, // 0=lambertian, 1=metal, 2=dielectric
    albedo: vec3f,
    fuzz: f32,
    refraction_index: f32,
}

struct Sphere {
    center: vec3f,
    radius: f32,
    material: MaterialType,
}

struct Ray {
    origin: vec3f,
    direction: vec3f,
    time: f32,
}

struct HitRecord {
    p: vec3f,
    normal: vec3f,
    t: f32,
    front_face: bool,
    material_id: u32,
}

struct Interval {
    min: f32,
    max: f32,
}

// Uniform buffer for camera settings and state
@group(0) @binding(0)
var<uniform> camera: Camera;

// Storage buffer for spheres
@group(0) @binding(1)
var<storage, read> spheres: array<Sphere>;

// Storage buffer for output texture data
@group(0) @binding(2)
var<storage, read_write> output: array<vec4f>;

// Constants 
const MAX_SPHERES = 1000;
const PI = 3.1415926535897932385;

// Random number generation
var<private> seed: vec3u;

fn init_rand(invocation_id: vec3u, frame_number: u32) {
    seed = invocation_id ^ vec3u(frame_number * 719393u, frame_number * 271823u, frame_number * 435613u);
}

fn rand() -> f32 {
    // PCG random number generator (simplified)
    seed.x = seed.x * 747796405u + 2891336453u;
    seed.y = seed.y * 747796405u + 2891336453u;
    seed.z = seed.z * 747796405u + 2891336453u;
    
    let word = ((seed.x >> ((seed.y >> 28u) + 4u)) ^ seed.x) * 277803737u;
    let result = (word >> 22u) ^ word;
    
    return f32(result) / 4294967295.0; // Convert to [0, 1)
}

fn rand_in_unit_sphere() -> vec3f {
    var p: vec3f;
    while(true) {
        p = vec3f(rand() * 2.0 - 1.0, rand() * 2.0 - 1.0, rand() * 2.0 - 1.0);
        if (dot(p, p) < 1.0) {
            break;
        }
    }
    return p;
}

fn rand_unit_vector() -> vec3f {
    return normalize(rand_in_unit_sphere());
}

fn rand_in_unit_disk() -> vec3f {
    var p: vec3f;
    while(true) {
        p = vec3f(rand() * 2.0 - 1.0, rand() * 2.0 - 1.0, 0.0);
        if (dot(p, p) < 1.0) {
            break;
        }
    }
    return p;
}

fn near_zero(v: vec3f) -> bool {
    let s = 1e-8;
    return (abs(v.x) < s) && (abs(v.y) < s) && (abs(v.z) < s);
}

fn reflect(v: vec3f, n: vec3f) -> vec3f {
    return v - 2.0 * dot(v, n) * n;
}

fn refract(uv: vec3f, n: vec3f, etai_over_etat: f32) -> vec3f {
    let cos_theta = min(dot(-uv, n), 1.0);
    let r_out_perp = etai_over_etat * (uv + cos_theta * n);
    let r_out_parallel = -sqrt(abs(1.0 - dot(r_out_perp, r_out_perp))) * n;
    return r_out_perp + r_out_parallel;
}

fn reflectance(cosine: f32, ref_idx: f32) -> f32 {
    // Schlick's approximation for reflectance
    var r0 = (1.0 - ref_idx) / (1.0 + ref_idx);
    r0 = r0 * r0;
    return r0 + (1.0 - r0) * pow((1.0 - cosine), 5.0);
}

fn sample_square() -> vec2f {
    return vec2f(rand() - 0.5, rand() - 0.5);
}

fn defocus_disk_sample(cam: Camera) -> vec3f {
    let p = rand_in_unit_disk();
    return cam.center + cam.defocus_disk_u * p.x + cam.defocus_disk_v * p.y;
}

fn get_ray(cam: Camera, i: f32, j: f32) -> Ray {
    let offset = sample_square();
    
    let pixel_sample = cam.pixel00_loc + 
                      ((i + offset.x) * cam.pixel_delta_u) + 
                      ((j + offset.y) * cam.pixel_delta_v);
    
    let ray_origin = select(cam.center, defocus_disk_sample(cam), cam.defocus_angle > 0.0);
    let ray_direction = pixel_sample - ray_origin;
    let ray_time = rand();
    
    return Ray(ray_origin, ray_direction, ray_time);
}

fn set_face_normal(r: Ray, outward_normal: vec3f) -> vec3f {
    let front_face = dot(r.direction, outward_normal) < 0.0;
    return select(-outward_normal, outward_normal, front_face);
}

fn hit_sphere(ray: Ray, sphere: Sphere, ray_t: Interval, rec: ptr<function, HitRecord>) -> bool {
    // The vector from ray origin to sphere center
    let oc = ray.origin - sphere.center;
    
    // Using the quadratic formula for ray-sphere intersection
    let a = dot(ray.direction, ray.direction);
    let half_b = dot(oc, ray.direction);
    let c = dot(oc, oc) - sphere.radius * sphere.radius;
    
    // Discriminant determines if the ray hits the sphere
    let discriminant = half_b * half_b - a * c;
    
    // If discriminant is negative, no intersection
    if (discriminant < 0.0) {
        return false;
    }
    
    // Find the closest intersection point that's within our valid range
    let sqrtd = sqrt(discriminant);
    
    // Try the closer intersection first
    var root = (-half_b - sqrtd) / a;
    if (root < ray_t.min || root > ray_t.max) {
        // If the closer intersection is out of range, try the farther one
        root = (-half_b + sqrtd) / a;
        if (root < ray_t.min || root > ray_t.max) {
            // Both intersections are out of range
            return false;
        }
    }
    
    // We have a valid intersection, fill in the hit record
    (*rec).t = root;
    (*rec).p = ray.origin + root * ray.direction;
    
    // Calculate the normal, ensuring it points outward from the surface
    let outward_normal = ((*rec).p - sphere.center) / sphere.radius;
    
    // Determine if the ray is hitting from inside or outside
    let front_face = dot(ray.direction, outward_normal) < 0.0;
    
    // Set the normal to always point against the ray direction
    (*rec).normal = select(-outward_normal, outward_normal, front_face);
    (*rec).front_face = front_face;
    
    return true;
}

fn hit_world(ray: Ray, ray_t: Interval, rec: ptr<function, HitRecord>) -> bool {
    var temp_rec: HitRecord;
    var hit_anything = false;
    var closest_so_far = ray_t.max;
    
    // Get the number of spheres in the buffer
    let sphere_count = arrayLength(&spheres);
    
    for (var i = 0u; i < sphere_count; i++) {
        let temp_interval = Interval(ray_t.min, closest_so_far);
        if (hit_sphere(ray, spheres[i], temp_interval, &temp_rec)) {
            hit_anything = true;
            closest_so_far = temp_rec.t;
            *rec = temp_rec;
            (*rec).material_id = i; // Store sphere index as material ID
        }
    }
    
    return hit_anything;
}

fn scatter_lambertian(material: MaterialType, r_in: Ray, rec: HitRecord, attenuation: ptr<function, vec3f>, scattered: ptr<function, Ray>) -> bool {
    var scatter_direction = rec.normal + rand_unit_vector();
    
    // Catch degenerate scatter direction
    if (near_zero(scatter_direction)) {
        scatter_direction = rec.normal;
    }
    
    *scattered = Ray(rec.p, scatter_direction, r_in.time);
    *attenuation = material.albedo;
    return true;
}

fn scatter_metal(material: MaterialType, r_in: Ray, rec: HitRecord, attenuation: ptr<function, vec3f>, scattered: ptr<function, Ray>) -> bool {
    let reflected = reflect(normalize(r_in.direction), rec.normal);
    *scattered = Ray(rec.p, reflected + material.fuzz * rand_unit_vector(), r_in.time);
    *attenuation = material.albedo;
    return dot((*scattered).direction, rec.normal) > 0.0;
}

fn scatter_dielectric(material: MaterialType, r_in: Ray, rec: HitRecord, attenuation: ptr<function, vec3f>, scattered: ptr<function, Ray>) -> bool {
    *attenuation = vec3f(1.0, 1.0, 1.0);
    let refraction_ratio = select(material.refraction_index, 1.0 / material.refraction_index, rec.front_face);
    
    let unit_direction = normalize(r_in.direction);
    let cos_theta = min(dot(-unit_direction, rec.normal), 1.0);
    let sin_theta = sqrt(1.0 - cos_theta * cos_theta);
    
    let cannot_refract = refraction_ratio * sin_theta > 1.0;
    var direction: vec3f = vec3f(0.0, 0.0, 0.0);
    
    if (cannot_refract || reflectance(cos_theta, refraction_ratio) > rand()) {
        direction = reflect(unit_direction, rec.normal);
    } else {
        direction = refract(unit_direction, rec.normal, refraction_ratio);
    }
    
    *scattered = Ray(rec.p, direction, r_in.time);
    return true;
}

fn scatter(sphere_idx: u32, r_in: Ray, rec: HitRecord, attenuation: ptr<function, vec3f>, scattered: ptr<function, Ray>) -> bool {
    let material = spheres[sphere_idx].material;
    
    if (material.material_type == 0u) { // Lambertian
        return scatter_lambertian(material, r_in, rec, attenuation, scattered);
    } else if (material.material_type == 1u) { // Metal
        return scatter_metal(material, r_in, rec, attenuation, scattered);
    } else if (material.material_type == 2u) { // Dielectric
        return scatter_dielectric(material, r_in, rec, attenuation, scattered);
    }
    
    return false;
}

fn ray_color(r: Ray, max_depth: i32) -> vec3f {
    // Use an iterative approach instead of recursion for WGSL compatibility
    var current_ray = r;
    var current_attenuation = vec3f(1.0, 1.0, 1.0);
    var final_color = vec3f(0.0, 0.0, 0.0);
    
    // Loop for each bounce instead of using recursion
    for (var depth = 0; depth < max_depth; depth++) {
        var rec: HitRecord;
        
        // Check for intersection with any object
        if (hit_world(current_ray, Interval(0.001, 1e30), &rec)) {
            // We hit something, now compute material interaction
            let material = spheres[rec.material_id].material;
            var scattered: Ray;
            var attenuation: vec3f;
            var scatter_success = false;
            
            // Process based on material type
            switch (material.material_type) {
                case 0u: { // Lambertian (diffuse)
                    // Generate a random scatter direction
                    var scatter_direction = rec.normal + rand_unit_vector();
                    
                    // Catch degenerate scatter direction
                    if (near_zero(scatter_direction)) {
                        scatter_direction = rec.normal;
                    }
                    
                    // Create the scattered ray
                    scattered = Ray(rec.p, scatter_direction, current_ray.time);
                    attenuation = material.albedo;
                    scatter_success = true;
                }
                case 1u: { // Metal (reflective)
                    // Reflect the incoming ray
                    let reflected = reflect(normalize(current_ray.direction), rec.normal);
                    
                    // Add some fuzz (randomness) based on material property
                    scattered = Ray(rec.p, reflected + material.fuzz * rand_unit_vector(), current_ray.time);
                    attenuation = material.albedo;
                    
                    // Only consider valid reflections (pointing away from surface)
                    scatter_success = dot(scattered.direction, rec.normal) > 0.0;
                }
                case 2u: { // Dielectric (glass/water)
                    attenuation = vec3f(1.0, 1.0, 1.0); // No attenuation (clear material)
                    
                    // Compute refraction ratio based on whether we're entering or exiting
                    let refraction_ratio = select(material.refraction_index, 1.0 / material.refraction_index, rec.front_face);
                    
                    // Compute angles for Snell's law
                    let unit_direction = normalize(current_ray.direction);
                    let cos_theta = min(dot(-unit_direction, rec.normal), 1.0);
                    let sin_theta = sqrt(1.0 - cos_theta * cos_theta);
                    
                    // Determine if we must reflect due to physics (total internal reflection)
                    let cannot_refract = refraction_ratio * sin_theta > 1.0;
                    var direction: vec3f;
                    
                    // Choose reflect or refract
                    if (cannot_refract || reflectance(cos_theta, refraction_ratio) > rand()) {
                        direction = reflect(unit_direction, rec.normal);
                    } else {
                        direction = refract(unit_direction, rec.normal, refraction_ratio);
                    }
                    
                    scattered = Ray(rec.p, direction, current_ray.time);
                    scatter_success = true;
                }
                default: {
                    // Unknown material type
                    return vec3f(1.0, 0.0, 1.0); // Magenta for debugging
                }
            }
            
            if (scatter_success) {
                // Update the ray and attenuation for the next iteration
                current_attenuation *= attenuation;
                current_ray = scattered;
            } else {
                // Ray was absorbed
                return vec3f(0.0, 0.0, 0.0);
            }
        } else {
            // Ray hit nothing - return sky color
            let unit_direction = normalize(current_ray.direction);
            let t = 0.5 * (unit_direction.y + 1.0);
            let sky = (1.0 - t) * vec3f(1.0, 1.0, 1.0) + t * vec3f(0.5, 0.7, 1.0);
            
            // Multiply sky color by accumulated attenuation and exit the loop
            final_color = current_attenuation * sky;
            return final_color;  // Exit the loop early when we hit the sky
        }
    }
    
    // If we've exceeded the bounce limit, return black (fully absorbed)
    return vec3f(0.0, 0.0, 0.0);
}

// Helper functions
fn contains(i: Interval, x: f32) -> bool {
    return i.min <= x && x <= i.max;
}

fn surrounds(i: Interval, x: f32) -> bool {
    return i.min < x && x < i.max;
}

fn linear_to_gamma(linear: vec3f) -> vec3f {
    return vec3f(sqrt(linear.x), sqrt(linear.y), sqrt(linear.z));
}

@compute @workgroup_size(8, 8, 1)
fn cs_main(@builtin(global_invocation_id) global_id: vec3u) {
    // ABSOLUTELY MINIMAL SHADER - only red color for every pixel
    let width = u32(camera.image_width);
    let height = u32(camera.image_height);
    
    // Make sure we're within bounds
    if (global_id.x < width && global_id.y < height) {  // WGSL uses && like C/C++, not 'and'
        let idx = global_id.y * width + global_id.x;
        
        // Every pixel is just solid red (255, 0, 0)
        output[idx] = vec4f(1.0, 0.0, 0.0, 1.0);
    }
}

// Debug function to make sure we're actually rendering something
fn debug_color(position: vec2u) -> vec3f {
    // Create a simple pattern to verify the shader is running
    let checkerSize = 16u;
    let isEvenX = (position.x / checkerSize) % 2u == 0u;
    let isEvenY = (position.y / checkerSize) % 2u == 0u;
    
    if (isEvenX == isEvenY) {
        return vec3f(0.8, 0.8, 0.8);
    } else {
        return vec3f(0.2, 0.2, 0.2);
    }
}

// For backward compatibility - these functions are not used for ray tracing
@vertex
fn vs_main(@builtin(vertex_index) in_vertex_index: u32) -> @builtin(position) vec4f {
    var p = vec2f(0.0, 0.0);
    if (in_vertex_index == 0u) {
        p = vec2f(-1.0, -1.0);
    } else if (in_vertex_index == 1u) {
        p = vec2f(3.0, -1.0);
    } else {
        p = vec2f(-1.0, 3.0);
    }
    return vec4f(p, 0.0, 1.0);
}

@fragment
fn fs_main() -> @location(0) vec4f {
    return vec4f(0.0, 0.0, 0.0, 1.0);
}