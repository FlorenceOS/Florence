const source_blob = @embedFile(@import("build_options").source_blob_path);
const iterate_files = @import("lib/tar.zig").iterate_files;

const std = @import("std");

const logger = @import("logger.zig");
const log = logger.log;
const hexdump = logger.hexdump;

fn should_skip_file(file: anytype) bool {
  if(file.file_contents.len < 5) // Probably not a valid source file
    return true;
  return false;
}

const SourceInfo = struct {
  num_files: usize = 0,
  num_lines: usize = 0,
};

const info = {
  @setEvalBranchQuota(10000000);

  var temp_info: SourceInfo = .{};
  var iterator = iterate_files(source_blob) catch unreachable;

  while(iterator.has_file): (iterator.next()) {
    if(should_skip_file(iterator))
      continue;

    var file_lines: usize = 1;
    for(iterator.file_contents) |chr| {
      if(chr == '\n')
        file_lines += 1;
    }
    temp_info.num_lines += file_lines;
    temp_info.num_files += 1;
  }

  return temp_info;
};

const File = struct {
  name: []const u8,
  lines: [][]const u8,

  pub fn getLine(self: *const @This(), line: usize) ![]const u8 {
    if(line >= self.lines.len)
      return error.LineNotFound;

    return self.lines[line];
  }
};

const Source = struct {
  lines: [info.num_lines][]const u8,
  files: [info.num_files]File,

  pub fn getFile(self: *const @This(), filename: []const u8) !*const File {
    for(self.files) |*f| {
      if(std.mem.eql(u8, filename, f.name))
        return f;
    }

    return error.FileNotFound;
  }

  pub fn getFileLine(self: *const @This(), filename: []const u8, line: usize) ![]const u8 {
    const f = try self.getFile(filename);
    const l = try f.getLine(line);
    return l;
  }
};

const source = {
  @setEvalBranchQuota(10000000);

  var source_temp: Source = undefined;

  var current_file: usize = 0;
  var current_line: usize = 0;

  var iterator = iterate_files(source_blob) catch unreachable;

  while(iterator.has_file): (iterator.next()) {
    if(should_skip_file(iterator))
      continue;

    var file_lines = 1;
    var content = iterator.file_contents;
    var offset: u64 = 0;
    while(offset < content.len): (offset += 1) {
      if(content[offset] == '\n') {
        source_temp.lines[current_line + file_lines - 1] = content[0..offset];
        content = content[offset..];
        file_lines += 1;
      }
    }
    source_temp.lines[current_line + file_lines - 1] = content;

    source_temp.files[current_file] = .{
      .name = iterator.file_name,
      .lines = source_temp.lines[current_line..current_line + file_lines],
    };

    current_line += file_lines;
    current_file += 1;

  }

  return source_temp;
};

pub fn dump_source() void {
  log("Entire kernel source: {}, {}\n", .{source, source.getFileLine("build.zig", 7) });
}
