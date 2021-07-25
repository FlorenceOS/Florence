usingnamespace @import("root").preamble;

pub const debug_allocator = &debug_allocator_state.allocator;

extern var __debug_info_start: u8;
extern var __debug_info_end: u8;
extern var __debug_abbrev_start: u8;
extern var __debug_abbrev_end: u8;
extern var __debug_str_start: u8;
extern var __debug_str_end: u8;
extern var __debug_line_start: u8;
extern var __debug_line_end: u8;
extern var __debug_ranges_start: u8;
extern var __debug_ranges_end: u8;

var debug_info = std.dwarf.DwarfInfo{
    .endian = os.platform.endian,
    .debug_info = undefined,
    .debug_abbrev = undefined,
    .debug_str = undefined,
    .debug_line = undefined,
    .debug_ranges = undefined,
};

var inited_debug_info = false;

var debug_allocator_bytes: [1024 * 1024]u8 = undefined;
var debug_allocator_state = std.heap.FixedBufferAllocator.init(debug_allocator_bytes[0..]);

fn initDebugInfo() void {
    if (!inited_debug_info) {
        //debug_info.debug_info = sliceSection(&__debug_info_start, &__debug_info_end);
        //debug_info.debug_abbrev = sliceSection(&__debug_abbrev_start, &__debug_abbrev_end);
        //debug_info.debug_str = sliceSection(&__debug_str_start, &__debug_str_end);
        //debug_info.debug_line = sliceSection(&__debug_line_start, &__debug_line_end);
        //debug_info.debug_ranges = sliceSection(&__debug_ranges_start, &__debug_ranges_end);
        os.log("Opening debug info\n", .{});
        std.dwarf.openDwarfDebugInfo(&debug_info, debug_allocator) catch |err| {
            os.log("Unable to open debug info: {s}\n", .{@errorName(err)});
            return;
        };
        os.log("Opened debug info\n", .{});
        inited_debug_info = true;
    }
}

fn sliceSection(start: *u8, end: *u8) []const u8 {
    const s = @ptrToInt(start);
    const e = @ptrToInt(end);
    return @intToPtr([*]const u8, s)[0 .. e - s];
}

fn printAddr(ip: usize) void {
    var compile_unit = debug_info.findCompileUnit(ip) catch |err| {
        os.log("Couldn't find the compile unit at {x}: {s}\n", .{ ip, @errorName(err) });
        return;
    };

    var line_info = debug_info.getLineNumberInfo(compile_unit.*, ip) catch |err| {
        os.log("Couldn't find the line info at {x}: {s}\n", .{ ip, @errorName(err) });
        return;
    };

    printInfo(line_info, ip, debug_info.getSymbolName(ip));
}

fn printInfo(line_info: std.debug.LineInfo, ip: usize, symbol_name: ?[]const u8) void {}

pub fn dumpFrame(bp: usize, ip: usize) void {
    os.log("Dumping ip=0x{x}, bp=0x{x}\n", .{ ip, bp });
    initDebugInfo();

    printAddr(ip);

    var it = std.debug.StackIterator.init(null, bp);
    while (it.next()) |addr| {
        printAddr(addr);
    }
}

pub fn dumpStackTrace(trace: *std.builtin.StackTrace) void {
    initDebugInfo();

    for (trace.instruction_addresses[trace.index..]) |addr| {
        printAddr(addr);
    }
}

pub fn dumpCurrentTrace() void {
    var it = std.debug.StackIterator.init(@returnAddress(), @frameAddress());
    while(it.next()) |addr| {
        printAddr(addr);
    }
}
