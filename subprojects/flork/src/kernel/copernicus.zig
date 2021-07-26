usingnamespace @import("root").preamble;

const build_options = @import("build_options");
const copernicus_data = @embedFile(build_options.copernicus_path);

pub fn getBaseAddr() usize {
    return std.mem.readIntLittle(usize, copernicus_data[0..8]);
}

pub fn getDataOffset() usize {
    return std.mem.readIntLittle(usize, copernicus_data[8..16]);
}

pub fn getRodataOffset() usize {
    return std.mem.readIntLittle(usize, copernicus_data[16..24]);
}

pub fn getBlob() []const u8 {
    return copernicus_data[32..];
}
