const std = @import("std");
const ImageRegion = @import("image_region.zig").ImageRegion;

// Buffer for a region. Useful when you want to read from your buffer, without having to do expensive mmio.
pub const SingleBuffer = struct {
    buffered_region: ImageRegion,
    backing_region: *ImageRegion,

    fn invalidate(region: *ImageRegion, x: usize, y: usize, width: usize, height: usize) void {
        const self = @fieldParentPtr(@This(), "buffered_region", region);
        self.backing_region.drawImageSameFmt(self.buffered_region.subregion(x, y, width, height), x, y, true);
    }

    pub fn init(self: *@This(), allocator: std.mem.Allocator, backing: *ImageRegion) !void {
        self.* = .{
            .buffered_region = .{
                .bytes = try allocator.alloc(u8, backing.height * backing.pitch),
                .height = backing.height,
                .pitch = backing.pitch,
                .width = backing.width,
                .pixel_format = backing.pixel_format,
                .invalidateRectFunc = invalidate,
            },
            .backing_region = backing,
        };
    }
};
