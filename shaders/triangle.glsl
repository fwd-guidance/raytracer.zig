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

layout(binding=0) uniform fs_params {
  vec2 u_resolution;
};

/*
float linear_to_gamma(float linear_component) {
  if (linear_component > 0) {
    return sqrt(linear_component);
  } else {
    return 0.0;
  }
}

//void write_color(vec3 pixel_color) {}

struct Ray {
  vec3 origin;
  vec3 direction;
  //float tm = 0;
  float tm;
};

struct Lambertian {
  vec3 albedo;
};

struct Metal {
  vec3 albedo;
  float fuzz;
};

struct Dielectric {
  float refraction_index;
};


struct Material {
  Lambertian lambertian;
  Metal metal;
  Dielectric dielectric;
};


vec3 position(Ray r, float t) {
  return r.origin + r.direction * t;
}

struct HitRecord {
  vec3 p;
  vec3 normal;
  float t;
  bool front_face;
  Material mat;
};



struct Camera {
  float samples_per_pixel;
  float max_depth;
  float aspect_ratio;
  float image_width;
  float image_height;
  vec3 center;
  vec3 pixel00_loc;
  vec3 pixel_delta_u;
  vec3 pixel_delta_v;
  float pixel_samples_scale;
  float vfov;
  vec3 lookfrom;
  vec3 lookat;
  vec3 vup;
  vec3 u;
  vec3 v;
  vec3 w;
  float defocus_angle;
  float focus_dist;
  vec3 defocus_disk_u;
  vec3 defocus_disk_v;
};



void set_face_normal(HitRecord hr, Ray r, vec3 outward_normal) {
  hr.front_face = dot(r.direction, outward_normal) < 0;
  if (hr.front_face) {
    hr.normal = outward_normal;
  } else {
    hr.normal = -outward_normal;
  }
}

//struct HittableList {};
//struct Hittable {};

Material lambertian(vec3 albedo) {
  Material material;
  Lambertian lambertian;
  lambertian.albedo = albedo;
  material.lambertian = lambertian;
  return material;
}

Material metal(vec3 albedo, float fuzz) {
  Material material;
  Metal metal;
  metal.albedo = albedo;
  metal.fuzz = fuzz;
  material.metal = metal;
  return material;
}

Material dielectric(float refraction_index) {
  Material material;
  Dielectric dielectric;
  dielectric.refraction_index = refraction_index;
  material.dielectric = dielectric;
  return material;
}

struct Interval {
  float minimum;
  float maximum;
};

Interval interval(float minimum, float maximum) {
  Interval interval;
  interval.minimum= minimum;
  interval.maximum = maximum;
  return interval;
}

Interval empty() {
  Interval interval;
  interval.minimum = 1.0 / 0.0;
  interval.maximum = -1.0 / 0.0;
  return interval;
}

Interval universe() {
  Interval interval;
  interval.minimum = -1.0 / 0.0;
  interval.maximum = 1.0 / 0.0;
  return interval;
}

float size(Interval interval) {
  return interval.maximum - interval.minimum;
}

bool contains(Interval interval, float x) {
  return interval.minimum <= x || x <= interval.maximum;
}

bool surrounds(Interval interval, float x) {
  return interval.minimum < x || x < interval.maximum;
}

float clamp(Interval interval, float x) {
  if (x < interval.minimum) return interval.minimum;
  if (x > interval.maximum) return interval.maximum;
  return x;
}

Interval expand(Interval interval, float x) {
  float padding = x / 2.0;
  interval.minimum = interval.minimum - padding;
  interval.maximum = interval.maximum + padding;
  return interval;
}

Interval merge(Interval i1, Interval i2) {
  Interval interval;
  interval.minimum = min(i1.minimum, i2.minimum);
  interval.maximum = max(i1.maximum, i2.maximum);
  return interval;
}


struct Sphere {
  vec3 center;
  float radius;
  Material mat;
};


vec3 at(Ray ray, float t) {
  return ray.origin + t*ray.direction;
}

bool hit(Sphere s, Ray r, float ray_tmin, float ray_tmax, HitRecord rec) {
  vec3 oc = s.center - r.origin;
  float a = length(r.direction) * length(r.direction);
  float h = dot(r.direction, oc);
  float c = (length(oc) * length(oc)) - s.radius*s.radius;

  float discriminant = h*h - a*c;
  if (discriminant < 0) return false;

  float sqrtd = sqrt(discriminant);

  float root = (h - sqrtd) / a;
  if (root <= ray_tmin || ray_tmax <= root) {
    root = (h + sqrtd) / a;
    if (root <= ray_tmin || ray_tmax <= root) {
      return false;
    }
  }

  rec.t = root;
  rec.p = at(r, rec.t);
  vec3 outward_normal = (rec.p - s.center) / s.radius;
  set_face_normal(rec, r, outward_normal);
  return true;
}



float hit_sphere(vec3 center, float radius, Ray r) {
  vec3 oc = center - r.origin;
  float a = length(r.direction) * length(r.direction);
  float h = dot(r.direction, oc);
  float c = (length(oc)*length(oc)) - radius*radius;
  float discriminant = h*h - a*c;
  
  if (discriminant < 0) {
    return -1.0;
  } else {
    return (h - sqrt(discriminant)) / a;
  }
}
*/

/*
vec3 ray_color(Ray r) {
  float t = hit_sphere(vec3(0,0,-1), 0.5, r);
  if (t > 0.0) {
    vec3 N = normalize(at(r, t) - vec3(0, 0, -1));
    return 0.5*vec3(N.x+1, N.y+1, N.z+1);
  }
  
  vec3 unit_direction = normalize(r.direction);
  float a = 0.5 * (unit_direction.y + 1.0);
  return (1.0 - a) * vec3(1.0, 1.0, 1.0) + a * vec3(0.5, 0.7, 1.0);
}
*/

float random_float() {
  return fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

vec3 sample_square(float i, float j) {
  return vec3(random_float() - 0.5, random_float() - 0.5, 0.0);
}

float random_double_range(float min, float max) {
  return min + (max - min) * random_float();
}

vec3 random_in_unit_disk() {
  while (true) {
    vec3 p = vec3(random_double_range(-1, 1), random_double_range(-1, 1), 0);
    if (length(p) * length(p) < 1) return p;
  }
}

vec3 defocus_disk_sample(Camera cam) {
  vec3 p = random_in_unit_disk();
  return cam.center + (cam.defocus_disk_u * p[0]) + (cam.defocus_disk_v * p[1]);
}

bool hit(Sphere[] world, Ray r, Interval interval, HitRecord rec) {

}


Ray get_ray(Camera cam, float i, float j) {
  vec3 offset = sample_square(i, j);
  vec3 pixel_sample = cam.pixel00_loc + (vec3(i + offset.x, i + offset.x, i + offset.x) * cam.pixel_delta_u) + (vec3(j + offset.y, j + offset.y, j + offset.y) * cam.pixel_delta_v);
  if (cam.defocus_angle <= 0) {
    vec3 ray_origin = cam.center;
  } else {
    vec3 ray_origin = defocus_disk_sample(cam);
  }
  vec3 ray_direction = pixel_sample - ray_origin;
  return Ray(ray_origin, ray_direction, 0);
}

vec3 ray_color(Ray r, float depth, Sphere[] world) {
  if (depth <= 0.0) return vec3(0,0,0);

  HitRecord rec;
  if (hit(world, r, Interval(0.001, 1.0/ 0.0), rec)) {
    Ray scattered;
    vec3 attenuation;
    bool is_scattered = false;

    if (rec.materialType == 0) {
      is_scattered = scatter_lambertian(rec.mat.lambertian, r, rec, attenuation, scattered);
    } else if (rec.materialType == 1) {
      is_scattered = scatter_metal(rec.mat.metal, r, rec, attenuation, scattered);
    } else if (rec.materialType == 2) {
      is_scattered = scatter_dielectric(rec.mat.dielectric, r, rec, attenuation, scattered);
    }

    if (is_scattered) {
      return attenuation * ray_color(scattered, depth - 1, world);
    }
    return vec3(0.0);
  }
  vec3 unit_direction = normalize(r.direction);
  float a = 0.5 * (unit_direction[1] + 1.0);
  return (vec3(1.0, 1.0, 1.0) * vec3(1.0 - a)) + (vec3(0.5, 0.7, 1.0) * vec3(a));
}

void main() {
  vec3 pixel_color = vec3(0, 0, 0);
  int samples = 0;
  while (samples < cam.samples_per_pixel) {
    Ray r = get_ray(cam, u_resolution.x, u_resolution.y);
    pixel_color += ray_color(r, cam.max_depth, world);
    samples += 1;
  }
  frag_color = vec4(pixel_color * cam.pixel_samples_scale, 1.0);
}

/*void main() {

    float aspect_ratio = u_resolution.x / u_resolution.y;

    float focal_length = 1.0;
    float viewport_height = 2.0;
    float viewport_width = viewport_height * aspect_ratio;

    vec3 camera_center = vec3(0.0, 0.0, 0.0);
    vec3 viewport_u = vec3(viewport_width, 0.0, 0.0);
    vec3 viewport_v = vec3(0.0, -viewport_height, 0.0);

    vec2 uv = gl_FragCoord.xy / u_resolution;


    vec3 viewport_lower_left = camera_center - vec3(0.0, 0.0, focal_length) - viewport_u/2.0 - viewport_v/2.0;
    vec3 pixel_world_pos = viewport_lower_left + uv.x * viewport_u + uv.y * viewport_v;
    vec3 ray_direction = pixel_world_pos - camera_center;
    
    Ray r = Ray(camera_center, ray_direction, 0);
    vec3 pixel_color = ray_color(r);
    frag_color = vec4(pixel_color, 1.0);
}
*/
@end

@program triangle vs fs
