const os = @import("root").os;
const std = @import("std");

const build_options = @import("build_options");
const copernicus_data = @embedFile(build_options.copernicus_path);
const process = os.kernel.process;

const blob = copernicus_data[32..];

const text_base = std.mem.readIntLittle(usize, copernicus_data[0..8]);
const text_size = data_offset;
const text_offset = 0;
const text = copernicus_data[32 + text_offset ..][0..text_size];

const data_base = text_base + text_size;
const data_size = rodata_offset - data_offset;
const data_offset = std.mem.readIntLittle(usize, copernicus_data[8..16]);
const data = copernicus_data[32 + data_offset ..][0..data_size];

const rodata_base = data_base + data_size;
const rodata_size = blob.len - rodata_offset;
const rodata_offset = std.mem.readIntLittle(usize, copernicus_data[16..24]);
const rodata = copernicus_data[32 + rodata_offset ..][0..rodata_size];

var copernicus_text_obj = process.memory_object.staticMemoryObject(@as([]const u8, text), os.memory.paging.rx());
var copernicus_data_obj = process.memory_object.staticMemoryObject(@as([]const u8, data), os.memory.paging.rw());
var copernicus_rodata_obj = process.memory_object.staticMemoryObject(@as([]const u8, rodata), os.memory.paging.ro());

comptime {
    if (text_size == 0) {
        @compileError("No copernicus text section");
    }
}

pub fn map(addr_space: *process.address_space.AddrSpace) !usize {
    try addr_space.allocateAt(text_base, text_size);
    _ = try addr_space.lazyMap(text_base, text_size, try copernicus_text_obj.makeRegion());
    errdefer addr_space.freeAndUnmap(text_base, text_size);

    if (data_size > 0) {
        try addr_space.allocateAt(data_base, data_size);
        _ = try addr_space.lazyMap(data_base, data_size, try copernicus_data_obj.makeRegion());
        errdefer addr_space.freeAndUnmap(data_base, data_size);
    }

    if (rodata_size > 0) {
        try addr_space.allocateAt(rodata_base, rodata_size);
        _ = try addr_space.lazyMap(rodata_base, rodata_size, try copernicus_rodata_obj.makeRegion());
        errdefer addr_space.freeAndUnmap(rodata_base, rodata_size);
    }

    return text_base;
}
