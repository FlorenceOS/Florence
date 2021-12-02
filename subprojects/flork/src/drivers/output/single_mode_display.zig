const os = @import("root").os;
const graphics = @import("lib").graphics;
const output = os.drivers.output;

pub const SingleModeDisplay = struct {
    context: output.video.DisplayContext,

    /// Initialize everything except context.invalidateRectFunc
    pub fn init(
        self: *@This(),
        bytes: []u8,
        width: usize,
        height: usize,
        pitch: usize,
        format: graphics.pixel_format.PixelFormat,
        invalidateRectFunc: ?graphics.image_region.InvalidateRectFunc,
    ) void {
        self.context = .{
            .region = .{
                .width = width,
                .height = height,
                .pixel_format = format,

                .bytes = bytes,
                .pitch = pitch,
                .invalidateRectFunc = invalidateRectFunc,
            },
            .iterateModes = iterateModes,
            .setMode = setMode,
        };
    }

    fn iterateModes(
        ctx: *output.video.DisplayContext,
        caller_ctx: output.video.CallbackContext,
        callback: output.video.ModeCallback,
    ) void {
        // Current mode only
        const mode = output.video.DisplayMode{
            .static = .{
                .width = ctx.region.width,
                .height = ctx.region.height,
                .pixel_format = ctx.region.pixel_format,
                .pitch = ctx.region.pitch,
            },
        };
        callback(caller_ctx, &mode);
    }

    fn setMode(
        ctx: *output.video.DisplayContext,
        mode: *const output.video.DisplayMode,
    ) void {
        // Lmao just ignore
        _ = ctx;
        _ = mode;
    }
};
