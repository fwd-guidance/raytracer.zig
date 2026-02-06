const std = @import("std");
const c = @cImport({
    @cInclude("stb_image.h");
});

const red = [_]u8{ 255, 0, 0 };

pub const RTWImage = struct {
    fdata: ?[*]f32 = null,
    bdata: ?[]u8 = null,
    image_width: i32 = 0,
    image_height: i32 = 0,
    bytes_per_pixel: i32 = 3,
    bytes_per_scanline: i32 = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RTWImage {
        return .{ .allocator = allocator };
    }

    pub fn init_from_file(allocator: std.mem.Allocator, image_filename: []const u8) !RTWImage {
        var self = RTWImage.init(allocator);

        if (std.posix.getenv("RTW_IMAGES")) |imagedir| {
            const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ imagedir, image_filename });
            defer allocator.free(full_path);
            if (self.load(full_path)) {
                return self;
            }
        }

        // Hunt for the image file in likely locations
        const search_paths = [_][]const u8{
            "",
            "images/",
            "../images/",
            "../../images/",
            "../../../images/",
            "../../../../images/",
            "../../../../../images/",
            "../../../../../../images/",
        };

        for (search_paths) |prefix| {
            const full_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, image_filename });
            defer allocator.free(full_path);
            if (self.load(full_path)) {
                return self;
            }
        }

        std.debug.print("ERROR: Could not load image file '{s}'.\n", .{image_filename});
        return self;
    }
    pub fn deinit(self: *RTWImage) void {
        if (self.bdata) |data| {
            self.allocator.free(data);
            self.bdata = null;
        }
        if (self.fdata) |data| {
            c.stbi_image_free(data);
            self.fdata = null;
        }
    }

    fn load(self: *RTWImage, filename: []const u8) bool {
        // Need null-terminated string for C
        const filename_z = self.allocator.dupeZ(u8, filename) catch return false;
        defer self.allocator.free(filename_z);

        var n: i32 = 0; // Dummy out parameter: original components per pixel
        self.fdata = c.stbi_loadf(
            filename_z.ptr,
            &self.image_width,
            &self.image_height,
            &n,
            self.bytes_per_pixel,
        );

        if (self.fdata == null) return false;

        self.bytes_per_scanline = self.image_width * self.bytes_per_pixel;
        self.convertToBytes() catch return false;
        return true;
    }

    pub fn width(self: RTWImage) i32 {
        return if (self.fdata == null) 0 else self.image_width;
    }

    pub fn height(self: RTWImage) i32 {
        return if (self.fdata == null) 0 else self.image_height;
    }

    pub fn pixelData(self: RTWImage, x: i32, y: i32) [*]const u8 {
        // Return the address of the three RGB bytes of the pixel at x,y.
        // If there is no image data, returns red.
        if (self.bdata == null) return &red;

        const clamped_x = clamp(x, 0, self.image_width);
        const clamped_y = clamp(y, 0, self.image_height);

        const offset = @as(usize, @intCast(clamped_y * self.bytes_per_scanline + clamped_x * self.bytes_per_pixel));
        return self.bdata.?[offset..].ptr;
    }

    fn clamp(x: i32, low: i32, high: i32) i32 {
        // Return the value clamped to the range [low, high).
        if (x < low) return low;
        if (x < high) return x;
        return high - 1;
    }

    fn floatToByte(value: f32) u8 {
        if (value <= 0.0) return 0;
        if (value >= 1.0) return 255;
        return @intFromFloat(256.0 * value);
    }

    fn convertToBytes(self: *RTWImage) !void {
        // Convert the linear floating point pixel data to bytes
        const total_bytes = @as(usize, @intCast(self.image_width * self.image_height * self.bytes_per_pixel));

        const byte_data = try self.allocator.alloc(u8, total_bytes);

        // Iterate through all pixel components, converting from [0.0, 1.0] float values
        // to unsigned [0, 255] byte values
        var i: usize = 0;
        while (i < total_bytes) : (i += 1) {
            byte_data[i] = floatToByte(self.fdata.?[i]);
        }

        self.bdata = byte_data;
    }
};
