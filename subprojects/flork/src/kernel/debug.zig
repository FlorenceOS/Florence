usingnamespace @import("root").preamble;

const log = @import("lib").output.log.scoped(.{
    .prefix = "kernel/debug",
    .filter = .info,
});

pub const debug_allocator = &debug_allocator_state.allocator;

extern var __kernel_begin: u8;
extern var __kernel_end: u8;

var debug_info = std.dwarf.DwarfInfo{
    .endian = os.platform.endian,
    .debug_info = undefined,
    .debug_abbrev = undefined,
    .debug_str = undefined,
    .debug_line = undefined,
    .debug_ranges = undefined,
};

var inited_debug_info = false;

var debug_allocator_bytes: [16 * 1024 * 1024]u8 = undefined;
var debug_allocator_state = std.heap.FixedBufferAllocator.init(debug_allocator_bytes[0..]);

fn getSectionData(elf: [*]u8, shdr: []u8) []u8 {
    const offset = @intCast(usize, std.mem.readIntLittle(u64, shdr[24..][0..8]));
    const size = @intCast(usize, std.mem.readIntLittle(u64, shdr[32..][0..8]));
    return elf[offset .. offset + size];
}

fn getSectionName(names: []const u8, shdr: []u8) ?[]const u8 {
    const offset = @intCast(usize, std.mem.readIntLittle(u32, shdr[0..][0..4]));
    const len = std.mem.indexOf(u8, names[offset..], "\x00") orelse return null;
    return names[offset .. offset + len];
}

fn getShdr(elf: [*]u8, idx: u16) []u8 {
    const sh_offset = std.mem.readIntLittle(u64, elf[40 .. 40 + 8]);
    const sh_entsize = std.mem.readIntLittle(u16, elf[58 .. 58 + 2]);
    const off = sh_offset + sh_entsize * @intCast(usize, idx);
    return elf[off .. off + sh_entsize];
}

fn getSectionSlice(elf: [*]u8, section_name: []const u8) ![]u8 {
    const sh_strndx = std.mem.readIntLittle(u16, elf[62 .. 62 + 2]);
    const sh_num = std.mem.readIntLittle(u16, elf[60 .. 60 + 2]);

    if (sh_strndx > sh_num)
        return error.ShstrndxOutOfRange;

    const section_names = getSectionData(elf, getShdr(elf, sh_strndx));

    var i: u16 = 0;
    while (i < sh_num) : (i += 1) {
        const header = getShdr(elf, i);

        if (std.mem.eql(u8, getSectionName(section_names, header) orelse continue, section_name)) {
            const ret = getSectionData(elf, header);
            log.write(.info, "Found section {s}: {*}, {d}", .{ section_name, ret.ptr, ret.len });
            return ret;
        }
    }

    return error.SectionNotFound;
}

fn attemptLoadDebug(elf: [*]u8) !void {
    debug_info.debug_info = try getSectionSlice(elf, ".debug_info");
    debug_info.debug_abbrev = try getSectionSlice(elf, ".debug_abbrev");
    debug_info.debug_str = try getSectionSlice(elf, ".debug_str");
    debug_info.debug_line = try getSectionSlice(elf, ".debug_line");
    debug_info.debug_ranges = try getSectionSlice(elf, ".debug_ranges");

    try std.dwarf.openDwarfDebugInfo(&debug_info, debug_allocator);
}

pub fn addDebugElf(elf: [*]u8) void {
    if (inited_debug_info)
        @panic("Double debug info init!");

    attemptLoadDebug(elf) catch |err| {
        log.write(.crit, "Failed to load debug info: {e}", .{err});
        if (@errorReturnTrace()) |trace| {
            dumpStackTrace(trace);
        } else {
            log.write(.crit, "No error trace.", .{});
        }
        return;
    };

    inited_debug_info = true;
    log.write(.info, "Opened debug info!", .{});
}

fn printAddr(ip: usize) void {
    if (ip < @ptrToInt(&__kernel_begin))
        return;

    if (ip > @ptrToInt(&__kernel_end))
        return;

    if (inited_debug_info) {
        var compile_unit = debug_info.findCompileUnit(ip) catch |err| {
            log.write(.warn, "Couldn't find the compile unit at 0x{X}: {s}", .{ ip, @errorName(err) });
            return;
        };

        var line_info = debug_info.getLineNumberInfo(compile_unit.*, ip) catch |err| {
            log.write(.warn, "Couldn't find the line info at 0x{X}: {s}", .{ ip, @errorName(err) });
            return;
        };

        printInfo(line_info, ip, debug_info.getSymbolName(ip));
    } else {
        printInfo(null, ip, null);
    }
}

fn printInfo(line_info: ?std.debug.LineInfo, ip: usize, symbol_name: ?[]const u8) void {
    const l = log.start(null, "0x{X}: ", .{ip});

    if (line_info) |li| {
        log.cont(null, "{s}:{d}:{d} ", .{ li.file_name, li.line, li.column }, l);
    } else {
        log.cont(null, "<No line info> ", .{}, l);
    }

    if (symbol_name) |symname| {
        log.finish(null, "{s}", .{symname}, l);
    } else {
        log.finish(null, "<No symbol>", .{}, l);
    }
}

pub fn dumpFrame(bp: usize, ip: usize) void {
    log.write(null, "Dumping ip=0x{X}, bp=0x{X}", .{ ip, bp });

    printAddr(ip);

    var it = std.debug.StackIterator.init(null, bp);
    while (it.next()) |addr| {
        printAddr(addr);
    }
}

pub fn dumpStackTrace(trace: *std.builtin.StackTrace) void {
    if (trace.index <= trace.instruction_addresses.len) {
        for (trace.instruction_addresses[trace.index..]) |addr| {
            printAddr(addr);
        }
    }
}

pub fn dumpCurrentTrace() void {
    var it = std.debug.StackIterator.init(@returnAddress(), @frameAddress());
    while (it.next()) |addr| {
        printAddr(addr);
    }
}
