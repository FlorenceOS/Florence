const std = @import("std");

pub const PixelFormat = enum {
    rgb, // 24 bpp rgb
    rgba, // 32 bpp with alpha
    rgbx, // 32 bpp, alpha ignored

    pub fn bytesPerPixel(fmt: @This()) usize {
        return switch (fmt) {
            .rgb => 3,
            .rgba, .rgbx => 4,
        };
    }

    pub fn meaningfulBytesPerPixel(fmt: @This()) usize {
        return switch (fmt) {
            .rgb, .rgbx => 3,
            .rgba => 4,
        };
    }

    pub fn canReadManyAs(actual: @This(), candidate: @This()) bool {
        if (actual == candidate)
            return true;

        if (candidate == .rgbx and actual == .rgba)
            return true;

        return false;
    }

    pub fn canReadAs(actual: @This(), candidate: @This()) bool {
        if (actual.canReadManyAs(candidate))
            return true;

        switch (candidate) {
            .rgb => {
                switch (actual) {
                    .rgba, .rgbx => return true,
                    else => {},
                }
            },
            else => {},
        }

        return false;
    }

    // @TODO: Check if the following two always are correct... I think they are??
    pub fn canWriteMany(actual: @This(), candidate: @This()) bool {
        return candidate.canReadManyAs(actual);
    }

    pub fn canWrite(actual: @This(), candidate: @This()) bool {
        return candidate.canReadAs(actual);
    }

    pub fn hasAlpha(fmt: @This()) bool {
        return switch (fmt) {
            .rgba => true,
            else => false,
        };
    }
};

test "canReadAs" {
    try std.testing.expect(PixelFormat.rgba.canReadAs(.rgb));
    try std.testing.expect(PixelFormat.rgbx.canReadAs(.rgb));
    try std.testing.expect(PixelFormat.rgba.canReadAs(.rgbx));
    try std.testing.expect(!PixelFormat.rgbx.canReadAs(.rgba));
}

test "canReadManyAs" {
    try std.testing.expect(!PixelFormat.rgba.canReadManyAs(.rgb));
    try std.testing.expect(!PixelFormat.rgbx.canReadManyAs(.rgb));
    try std.testing.expect(PixelFormat.rgba.canReadManyAs(.rgbx));
    try std.testing.expect(!PixelFormat.rgbx.canReadManyAs(.rgba));
}
