const std = @import("std");

const os = @import("root").os;

var debug_allocator_bytes: [1024 * 1024]u8 = undefined;
var debug_allocator_state = std.heap.FixedBufferAllocator.init(debug_allocator_bytes[0..]);
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
    .endian = std.builtin.endian,
    .debug_info = undefined,
    .debug_abbrev = undefined,
    .debug_str = undefined,
    .debug_line = undefined,
    .debug_ranges = undefined,
};

var inited_debug_info = false;

fn init_debug_info() void {
    if (!inited_debug_info) {
        //debug_info.debug_info   = slice_section(&__debug_info_start, &__debug_info_end);
        //debug_info.debug_abbrev = slice_section(&__debug_abbrev_start, &__debug_abbrev_end);
        //debug_info.debug_str    = slice_section(&__debug_str_start, &__debug_str_end);
        //debug_info.debug_line   = slice_section(&__debug_line_start, &__debug_line_end);
        //debug_info.debug_ranges = slice_section(&__debug_ranges_start, &__debug_ranges_end);
        os.log("Opening debug info\n", .{});
        std.dwarf.openDwarfDebugInfo(&debug_info, debug_allocator) catch |err| {
            os.log("Unable to open debug info: {s}\n", .{@errorName(err)});
            return;
        };
        os.log("Opened debug info\n", .{});
        inited_debug_info = true;
    }
}

pub fn dump_frame(bp: usize, ip: usize) void {
    os.log("Dumping ip=0x{x}, bp=0x{x}\n", .{ ip, bp });
    init_debug_info();

    print_addr(ip);

    //var it = std.debug.StackIterator.init(null, bp);
    //while (it.next()) |addr| {
    //    print_addr(ip);
    //}
}

pub fn dump_stack_trace(trace: *std.builtin.StackTrace) void {
    init_debug_info();

    for (trace.instruction_addresses[trace.index..]) |addr| {
        print_addr(addr);
    }
}

fn slice_section(start: *u8, end: *u8) []const u8 {
    const s = @ptrToInt(start);
    const e = @ptrToInt(end);
    return @intToPtr([*]const u8, s)[0 .. e - s];
}

fn print_addr(ip: usize) void {
    var compile_unit = debug_info.findCompileUnit(ip) catch |err| {
        os.log("Couldn't find the compile unit at {x}: {s}\n", .{ ip, @errorName(err) });
        return;
    };

    var line_info = debug_info.getLineNumberInfo(compile_unit.*, ip) catch |err| {
        os.log("Couldn't find the line info at {x}: {s}\n", .{ ip, @errorName(err) });
        return;
    };

    print_info(line_info, ip, debug_info.getSymbolName(ip));
}

fn print_info(line_info: std.debug.LineInfo, ip: usize, symbol_name: ?[]const u8) void {}
