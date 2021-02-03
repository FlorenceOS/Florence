const os = @import("root").os;
const std = @import("std");

const source_blob = @embedFile(@import("build_options").source_blob_path);

pub fn file_line(filename: []const u8, line: usize) ![]const u8 {
    var iterator = os.lib.tar.iterate_files(source_blob) catch unreachable;
    while (iterator.has_file) : (iterator.next()) {
        if (!std.mem.endsWith(u8, filename, iterator.file_name)) {
            continue;
        }
        var content = iterator.file_contents;

        var current_line: usize = 1;
        var offset: usize = 0;

        while (offset < content.len) {
            if (content[offset] == '\n') {
                if (current_line == line) {
                    return content[0..offset];
                }
                current_line += 1;
                content = content[offset + 1 ..];
                offset = 0;
            } else {
                offset += 1;
            }
        }
        if (current_line == line)
            return content;
        return error.LineNotFound;
    }
    return error.FileNotFound;
}

pub fn source_line(sl: std.builtin.SourceLocation) ![]const u8 {
    return file_line(sl.file, sl.line);
}
