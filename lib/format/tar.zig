const std = @import("std");

const FileIterator = struct {
    has_file: bool,
    file_contents: []const u8,
    file_name: []const u8,
    remaining_blob: []const u8,

    pub fn next(self: *@This()) void {
        self.* = make_next(self.remaining_blob);
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

fn makeNext(blob: []const u8) file_iterator {
    if (blob.len < 0x400 or std.mem.eql(u8, blob[0x101..0x106], &[_]u8{0} ** 5)) {
        const empty_arr = [_]u8{};
        return file_iterator{
            .has_file = false,
            .file_contents = empty_arr[0..],
            .file_name = empty_arr[0..],
            .remaining_blob = empty_arr[0..],
        };
    }

    const size = getFileSize(blob);
    const size_round_up = ((size + 0x1FF) / 0x200) * 0x200;

    return file_iterator{
        .has_file = true,
        .file_contents = blob[0x200 .. 0x200 + size],
        .file_name = getFileName(blob),
        .remaining_blob = blob[0x200 + size_round_up ..],
    };
}

pub fn iterate(tar_blob: []const u8) !FileIsterator {
    return maxeNext(tar_blob);
}
