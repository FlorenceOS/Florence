usingnamespace @import("root").preamble;

const ImageRegion = lib.graphics.image_region.ImageRegion;

// Buffer for a region. Useful when you want to read from your buffer, without having to do expensive mmio.
pub const SingleBuffer = struct {
    buffered_region: ImageRegion,
    backing_region: *ImageRegion,

    fn invalidate(region: *ImageRegion, x: usize, y: usize, width: usize, height: usize) void {
        const self = @fieldParentPtr(@This(), "buffered_region", region);
        self.backing_region.drawImageSameFmt(self.buffered_region.subregion(x, y, width, height), x, y, true);
    }

    pub fn init(self: *@This(), backing: *ImageRegion) !void {
        self.* = .{
            .buffered_region = .{
                .bytes = try os.memory.pmm.phys_heap.alloc(u8, backing.height * backing.pitch),
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
