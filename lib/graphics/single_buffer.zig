const std = @import("std");
const ImageRegion = @import("image_region.zig").ImageRegion;

// Buffer for a region. Useful when you want to read from your buffer, without having to do expensive mmio.
pub const SingleBuffer = struct {
    backing_region: *ImageRegion,
    buffer: BufferWithInvalidateHook(invalidate),

    fn invalidate(r: *ImageRegion, hooked_buf: anytype, x: usize, y: usize, width: usize, height: usize) void {
        const self = @fieldParentPtr(@This(), "buffer", hooked_buf);
        self.backing_region.drawImageSameFmt(r.subregion(x, y, width, height), x, y, true);
    }

    pub fn region(self: *@This()) *ImageRegion {
        return self.buffer.region();
    }

    pub fn init(self: *@This(), allocator: std.mem.Allocator, backing: *ImageRegion) !void {
        self.* = .{
            .buffer = try BufferWithInvalidateHook(invalidate).initMatching(allocator, backing.*),
            .backing_region = backing,
        };
    }
};

pub fn BufferWithInvalidateHook(hook: anytype) type {
    return struct {
        buffered_region: ImageRegion,

        fn invalidate(r: *ImageRegion, x: usize, y: usize, width: usize, height: usize) void {
            const self = @fieldParentPtr(@This(), "buffered_region", r);
            @call(.{.modifier = .always_inline}, hook, .{r, self, x, y, width, height});
        }

        pub fn region(self: *@This()) *ImageRegion {
            return &self.buffered_region;
        }

        // Allocates a buffer with the same properties (height, width, pitch, pixel format) as the supplied buffer
        pub fn initMatching(allocator: std.mem.Allocator, match: ImageRegion) !@This() {
            return @This() {
                .buffered_region = .{
                    .bytes = try allocator.alloc(u8, match.height * match.pitch),
                    .height = match.height,
                    .pitch = match.pitch,
                    .width = match.width,
                    .pixel_format = match.pixel_format,
                    .invalidateRectFunc = invalidate,
                },
            };
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.buffered_region.bytes);
        }
    };
}
