const std = @import("std");

fn here(comptime p: []const u8) std.build.FileSource {
    const base = std.fs.path.dirname(@src().file) orelse ".";
    return .{ .path = base ++ "/" ++ p };
}

const Pkg = std.build.Pkg;

pub fn add(
    b: *std.build.Builder,
    exec: *std.build.LibExeObjStep,
    source_blob_path: ?[]const u8,
) !void {
    const source_blob_opts = b.addOptions();
    source_blob_opts.addOption(?[]const u8, "blob_path", source_blob_path);

    exec.addPackage(.{
        .name = "lib",
        .path = comptime here("lib.zig"),
        .dependencies = &[_]Pkg{
            source_blob_opts.getPackage("sources"),
        },
    });
}
