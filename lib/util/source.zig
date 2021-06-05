usingnamespace @import("root").preamble;

const tar = lib.format.tar;

fn getSourceBlob() ?[]const u8 {
    if (@import("build_options").source_blob_path) |path| {
        return @embedFile(path);
    }
    return null;
}

pub fn getFileLine(filename: []const u8, line: usize) ![]const u8 {
    const blob = getSourceBlob() orelse return error.FileNotFound;
    var iterator = tar.iterate(blob) catch unreachable;
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

pub fn getSourceLine(sl: std.builtin.SourceLocation) ![]const u8 {
    return getFileLine(sl.file, sl.line);
}
