usingnamespace @import("root").preamble;

const lib = @import("lib");

pub const VideoOutputContext = struct {
    displays: []DisplayContext,
};

pub const CallbackContext = usize;

pub const ModeCallback = fn (CallbackContext, *const DisplayMode) void;
pub const ModeIterator = fn (*DisplayContext, CallbackContext, ModeCallback) void;
pub const ModeSetter = fn (*DisplayContext, *const DisplayMode) void;

pub const DisplayContext = struct {
    region: lib.graphics.image_region.ImageRegion,

    iterateModes: ModeIterator,
    setMode: ModeSetter,
};

pub const Dynamicness = enum {
    dynamic,
    static,
};

pub const StaticMode = struct {
    width: usize,
    height: usize,
    pitch: usize,
    pixel_format: PixelFormat,
};

pub const DisplayMode = union(Dynamicness) {
    dynamic: struct {
        max_width: usize,
        max_height: usize,
        pixel_format: PixelFormat,
    },
    static: StaticMode,
};

pub const ModeRequest = union(Dynamicness) {
    dynamic: struct {
        width: usize,
        height: usize,
        pixel_format: PixelFormat,
    },
    static: StaticMode,
};

const PixelFormat = lib.graphics.pixel_format.PixelFormat;
