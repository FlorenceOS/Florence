const std = @import("std");

fn here(comptime p: []const u8) std.build.FileSource {
    const base = std.fs.path.dirname(@src().file) orelse ".";
    return .{ .path = base ++ "/" ++ p };
}

const Pkg = std.build.Pkg;

const internal_packages = struct {
    const atomic_queue = Pkg{
        .name = "atomic_queue",
        .path = here("containers/atomic_queue.zig"),
        .dependencies = &[_]Pkg{
            queue,
        },
    };

    const handle_table = Pkg{
        .name = "handle_table",
        .path = here("containers/handle_table.zig"),
    };

    const queue = Pkg{
        .name = "queue",
        .path = here("containers/queue.zig"),
    };

    const rbtree = Pkg{
        .name = "rbtree",
        .path = here("containers/rbtree.zig"),
    };

    const refcounted = Pkg{
        .name = "refcounted",
        .path = here("containers/refcounted.zig"),
    };

    const tar = Pkg{
        .name = "tar",
        .path = here("format/tar.zig"),
    };

    const color = Pkg{
        .name = "color",
        .path = here("graphics/color.zig"),
        .dependencies = &[_]Pkg{
            pixel_format,
        },
    };

    const font_renderer = Pkg{
        .name = "font_renderer",
        .path = here("graphics/font_renderer.zig"),
        .dependencies = &[_]Pkg{
            color,
            image_region,
            pixel_format,
        },
    };

    const glyph_printer = Pkg{
        .name = "glyph_printer",
        .path = here("graphics/glyph_printer.zig"),
        .dependencies = &[_]Pkg{
            color,
            image_region,
            pixel_format,
            scrolling_region,
        },
    };

    const image_region = Pkg{
        .name = "image_region",
        .path = here("graphics/image_region.zig"),
        .dependencies = &[_]Pkg{
            color,
            pixel_format,
            libalign,
        },
    };

    const pixel_format = Pkg{
        .name = "pixel_format",
        .path = here("graphics/pixel_format.zig"),
    };

    const scrolling_region = Pkg{
        .name = "scrolling_region",
        .path = here("graphics/scrolling_region.zig"),
        .dependencies = &[_]Pkg{
            color,
            image_region,
        },
    };

    const single_buffer = Pkg{
        .name = "single_buffer",
        .path = here("graphics/single_buffer.zig"),
        .dependencies = &[_]Pkg{
            image_region,
        },
    };

    const keyboard = Pkg{
        .name = "keyboard",
        .path = here("input/keyboard/keyboard.zig"),
    };

    const range_alloc = Pkg{
        .name = "range_alloc",
        .path = here("memory/range_alloc.zig"),
        .dependencies = &[_]Pkg{
            rbtree,
        },
    };

    const fmt = Pkg{
        .name = "fmt",
        .path = here("output/fmt.zig"),
    };

    const log = Pkg{
        .name = "log",
        .path = here("output/log.zig"),
        .dependencies = &[_]Pkg{
            fmt,
        },
    };

    const bitfields = Pkg{
        .name = "bitfields",
        .path = here("util/bitfields.zig"),
    };

    const bitset = Pkg{
        .name = "bitset",
        .path = here("util/bitset.zig"),
    };

    const callback = Pkg{
        .name = "callback",
        .path = here("util/callback.zig"),
    };

    const libalign = Pkg{
        .name = "libalign",
        .path = here("util/libalign.zig"),
    };

    const pointers = Pkg{
        .name = "pointers",
        .path = here("util/pointers.zig"),
    };

    const range = Pkg{
        .name = "range",
        .path = here("util/range.zig"),
    };

    const source = Pkg{
        .name = "source",
        .path = here("util/source.zig"),
        .dependencies = &[_]Pkg{
            tar,
        },
    };
};

pub const pkg = Pkg{
    .name = "lib",
    .path = here("lib.zig"),
    .dependencies = (blk: {
        comptime var result: []const Pkg = &[_]Pkg{};
        for (@typeInfo(internal_packages).Struct.decls) |p| {
            result = result ++ [_]Pkg{@field(internal_packages, p.name)};
        }
        break :blk result;
    }),
};
