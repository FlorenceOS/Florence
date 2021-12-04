const std = @import("std");

const FileIterator = struct {
    has_file: bool,
    file_contents: []const u8,
    file_name: []const u8,
    remaining_blob: []const u8,

    pub fn next(self: *@This()) void {
        self.* = makeNext(self.remaining_blob);
    }
};

fn getFileName(blob: []const u8) []const u8 {
    // Filename is at offset 0, up to 100 in length
    var len: usize = 0;
    while (blob[len] != 0)
        len += 1;

    return blob[0..len];
}

fn getFileSize(blob: []const u8) usize {
    // File size is at [124..135], octal encoded
    return std.fmt.parseUnsigned(usize, blob[124..135], 8) catch unreachable;
}

fn fileDataSpace(file_size: usize) usize {
    return ((file_size + 0x1FF) / 0x200) * 0x200;
}

fn makeNext(blob: []const u8) FileIterator {
    if (blob.len < 0x400 or !std.mem.eql(u8, blob[0x101..0x106], "ustar")) {
        const empty_arr = [_]u8{};
        return .{
            .has_file = false,
            .file_contents = empty_arr[0..],
            .file_name = empty_arr[0..],
            .remaining_blob = empty_arr[0..],
        };
    }

    const size = getFileSize(blob);

    return .{
        .has_file = true,
        .file_contents = blob[0x200 .. 0x200 + size],
        .file_name = getFileName(blob),
        .remaining_blob = blob[0x200 + fileDataSpace(size) ..],
    };
}

pub fn iterate(tar_blob: []const u8) !FileIterator {
    return makeNext(tar_blob);
}

fn addFile(
    parent_dir: std.fs.Dir,
    file_name: []const u8,
    path_buf: *std.BoundedArray(u8, 99),
    out_file: std.fs.File,
) !void {
    const f = try parent_dir.openFile(file_name, .{});
    defer f.close();

    var header = std.mem.zeroes([0x200]u8);
    std.mem.copy(u8, header[0..100], path_buf.slice());
    std.mem.copy(u8, header[path_buf.slice().len..100], file_name);
    std.mem.copy(u8, header[0x101..], "ustar  \x00");

    const file_size = try f.getEndPos();

    _ = std.fmt.formatIntBuf(header[124..135], file_size, 8, .lower, .{
        .fill = '0',
        .width = 135 - 124,
    });

    try out_file.writeAll(&header);
    try out_file.writeFileAllUnseekable(f, .{});
    try out_file.writer().writeByteNTimes(0, fileDataSpace(file_size) - file_size);
}

fn addDirChildren(
    parent_dir: std.fs.Dir,
    dir_name: []const u8,
    path_buf: *std.BoundedArray(u8, 99),
    out_file: std.fs.File,
    filter: Filter,
) anyerror!void {
    const path_buf_old_len = path_buf.slice().len;
    try path_buf.appendSlice(dir_name);
    try path_buf.append('/');
    defer path_buf.resize(path_buf_old_len) catch unreachable;

    const dir = try parent_dir.openDir(dir_name, .{
        .access_sub_paths = true,
        .iterate = true,
    });

    // For now we don't add directories to the tar archive,
    // because we never read them anyways

    var it = dir.iterate();
    while (try it.next()) |dent| {
        if (filter(dent.name, path_buf.slice(), dent.kind) == .Skip) continue;

        switch (dent.kind) {
            .File => try addFile(dir, dent.name, path_buf, out_file),
            .Directory => try addDirChildren(dir, dent.name, path_buf, out_file, filter),
            else => {},
        }
    }
}

pub const FilterResult = enum {
    Include,
    Skip,
};

pub const Kind = std.fs.Dir.Entry.Kind;

pub const Filter = fn (name: []const u8, parent_path: []const u8, kind: Kind) FilterResult;

pub fn create(path: []const u8, output_path: []const u8, filter: Filter) !void {
    var path_buf = try std.BoundedArray(u8, 99).init(0);
    _ = path_buf;
    _ = path;

    const out_file = try std.fs.createFileAbsolute(output_path, .{});
    defer out_file.close();

    try addDirChildren(std.fs.cwd(), path, &path_buf, out_file, filter);
}
