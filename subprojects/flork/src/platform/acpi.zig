const os = @import("root").os;
const std = @import("std");
const lib = @import("lib");

const log = lib.output.log.scoped(.{
    .prefix = "platform/acpi",
    .filter = .info,
}).write;

const paging = os.memory.paging;
const pci = os.platform.pci;

const libalign = lib.util.libalign;
const range = lib.util.range;

const RSDP = packed struct {
    signature: [8]u8,
    checksum: u8,
    oemid: [6]u8,
    revision: u8,
    rsdt_addr: u32,

    extended_length: u32,
    xsdt_addr: u64,
    extended_checksum: u8,
};

const SDTHeader = packed struct {
    signature: [4]u8,
    len: u32,
    revision: u8,
    checksum: u8,
    oem: [6]u8,
    oem_table: [8]u8,
    oem_revison: u32,
    creator_id: u32,
    creator_revision: u32,
};

const GenericAddrStructure = packed struct {
    addr_space: u8,
    bit_width: u8,
    bit_offset: u8,
    access_size: u8,
    base: u64,
};

const FADT = packed struct {
    header: SDTHeader,
    firmware_control: u32,
    dsdt: u32,

    res0: u8,

    profile: u8,
    sci_irq: u16,
    smi_command_port: u32,
    acpi_enable: u8,
    acpi_disable: u8,
    s4bios_req: u8,
    pstate_control: u8,
    pm1a_event_block: u32,
    pm1b_event_block: u32,
    pm1a_control_block: u32,
    pm1b_control_block: u32,
    pm2_control_block: u32,
    pm_timer_block: u32,
    gpe0_block: u32,
    gpe1_block: u32,
    pm1_event_length: u8,
    pm1_control_length: u8,
    pm2_control_length: u8,
    pm_timer_length: u8,
    gpe0_length: u8,
    gpe1_length: u8,
    gpe1_base: u8,
    cstate_control: u8,
    worst_c2_latency: u16,
    worst_c3_latency: u16,
    flush_size: u16,
    flush_stride: u16,
    duty_offset: u8,
    duty_width: u8,

    // cmos registers
    day_alarm: u8,
    month_alarm: u8,
    century: u8,

    // ACPI 2.0 fields
    iapc_boot_flags: u16,
    reserved2: u8,
    flags: u32,

    reset_register: GenericAddrStructure,
    reset_command: u8,
    arm_boot_flags: u16,
    minor_version: u8,

    x_firmware_control: u64,
    x_dsdt: u64,

    x_pm1a_event_block: GenericAddrStructure,
    x_pm1b_event_block: GenericAddrStructure,
    x_pm1a_control_block: GenericAddrStructure,
    x_pm1b_control_block: GenericAddrStructure,
    x_pm2_control_block: GenericAddrStructure,
    x_pm_timer_block: GenericAddrStructure,
    x_gpe0_block: GenericAddrStructure,
    x_gpe1_block: GenericAddrStructure,
};

comptime {
    std.debug.assert(@offsetOf(FADT, "dsdt") == 40);
    std.debug.assert(@offsetOf(FADT, "x_dsdt") == 140);
}

const lai = os.kernel.lai;

var rsdp_phys: ?os.platform.phys_ptr([*]u8) = null;
var rsdp: *RSDP = undefined;

pub fn register_rsdp(rsdp_in: os.platform.phys_ptr([*]u8)) void {
    rsdp_phys = rsdp_in;
}

fn locate_rsdp() ?os.platform.phys_ptr([*]u8) {
    // @TODO
    return null;
}

fn parse_MCFG(sdt: []u8) void {
    var offset: usize = 44;
    while (offset + 16 <= sdt.len) : (offset += 16) {
        var addr = std.mem.readIntNative(u64, sdt[offset..][0..8]);
        var lo_bus = sdt[offset + 10];
        const hi_bus = sdt[offset + 11];

        while (true) {
            pci.register_mmio(lo_bus, addr) catch |err| {
                log(.err, "ACPI: Unable to register PCI mmio: {e}", .{@errorName(err)});
            };

            if (lo_bus == hi_bus)
                break;

            addr += 1 << 20;
            lo_bus += 1;
        }
    }
}

fn signature_value(sdt: anytype) u32 {
    return std.mem.readIntNative(u32, sdt[0..4]);
}

fn get_sdt(addr: u64) []u8 {
    var result = os.platform.phys_slice(u8).init(addr, 8);
    result.len = std.mem.readIntNative(u32, result.to_slice_writeback()[4..8]);
    return result.to_slice_writeback();
}

fn parse_sdt(addr: usize) void {
    const sdt = get_sdt(addr);

    switch (signature_value(sdt)) {
        signature_value("FACP") => {}, // Ignore for now
        signature_value("SSDT") => {}, // Ignore for now
        signature_value("DMAR") => {}, // Ignore for now
        signature_value("ECDT") => {}, // Ignore for now
        signature_value("SBST") => {}, // Ignore for now
        signature_value("HPET") => {}, // Ignore for now
        signature_value("WAET") => {}, // Ignore for now
        signature_value("SPCR") => {}, // Ignore for now
        signature_value("GTDT") => {}, // Ignore for now
        signature_value("APIC") => {
            switch (os.platform.arch) {
                .x86_64 => @import("x86_64/apic.zig").handle_madt(sdt),
                else => log(.info, "ACPI: MADT found on unsupported architecture!", .{}),
            }
        },
        signature_value("MCFG") => {
            parse_MCFG(sdt);
        },
        else => log(.warn, "ACPI: Unknown SDT: '{s}' with size {d} bytes", .{ @as([]u8, sdt[0..4]), sdt.len }),
    }
}

fn parse_root_sdt(comptime T: type, addr: usize) void {
    const sdt = get_sdt(addr);

    var offset: u64 = 36;

    while (offset + @sizeOf(T) <= sdt.len) : (offset += @sizeOf(T)) {
        parse_sdt(std.mem.readIntNative(T, sdt[offset..][0..@sizeOf(T)]));
    }
}

export fn laihost_log(kind: c_int, str: [*:0]const u8) void {
    switch (kind) {
        lai.LAI_WARN_LOG => log(.warn, "LAI: {s}", .{str}),
        lai.LAI_DEBUG_LOG => log(.debug, "LAI: {s}", .{str}),
        else => log(null, "UNK: LAI {s}", .{str}),
    }
}

fn impl_laihost_scan_table(addr: usize, name: *const [4]u8, index: *c_int) ?*anyopaque {
    const table = get_sdt(addr);
    if (std.mem.eql(u8, table[0..4], name)) {
        if (index.* == 0) return @ptrCast(*anyopaque, table.ptr);
        index.* -= 1;
    }
    return null;
}

fn impl_laihost_scan_root(comptime T: type, addr: usize, name: *const [4]u8, index_c: c_int) ?*anyopaque {
    const sdt = get_sdt(addr);

    var index = index_c;
    var offset: u64 = 36;

    while (offset + @sizeOf(T) <= sdt.len) : (offset += @sizeOf(T)) {
        const paddr = std.mem.readIntNative(T, sdt[offset..][0..@sizeOf(T)]);
        if (impl_laihost_scan_table(paddr, name, &index)) |result|
            return result;
    }
    return lai.NULL;
}

export fn laihost_scan(name: *const [4]u8, index: c_int) ?*anyopaque {
    if (index == 0) {
        if (std.mem.eql(u8, name, "RSDT")) return @ptrCast(*anyopaque, get_sdt(rsdp.rsdt_addr).ptr);
        if (std.mem.eql(u8, name, "XSDT")) return @ptrCast(*anyopaque, get_sdt(rsdp.xsdt_addr).ptr);
        if (std.mem.eql(u8, name, "DSDT")) {
            const fadt = @ptrCast(*align(1) FADT, laihost_scan("FACP", 0) orelse return lai.NULL);
            if (fadt.dsdt != 0) return @ptrCast(*anyopaque, get_sdt(fadt.dsdt).ptr);
            if (fadt.x_dsdt != 0) return @ptrCast(*anyopaque, get_sdt(fadt.x_dsdt).ptr);
            return lai.NULL;
        }
    }
    switch (rsdp.revision) {
        0 => return impl_laihost_scan_root(u32, rsdp.rsdt_addr, name, index),
        2 => return impl_laihost_scan_root(u64, rsdp.xsdt_addr, name, index),
        else => unreachable,
    }
}

export fn laihost_panic(err: [*:0]const u8) noreturn {
    has_lai_acpi = false;
    log(.err, "LAI: {s}", .{err});
    @panic("LAI PANIC");
}

export fn laihost_map(addr: usize, size: usize) ?*anyopaque {
    _ = size;
    return os.platform.phys_ptr(*anyopaque).from_int(addr).get_uncached();
}

export fn laihost_unmap(ptr: *anyopaque, size: usize) void {
    _ = ptr;
    _ = size;
}

export fn laihost_handle_amldebug(_: *anyopaque) void {}

export fn laihost_sleep(some_unit_of_time: u64) void {
    _ = some_unit_of_time;
    @panic("laihost_sleep");
}

export fn laihost_sync_wait(state: *lai.lai_sync_state, value: u32, deadline: u64) void {
    _ = state;
    _ = value;
    _ = deadline;
    @panic("laihost_sync_wait");
}

export fn laihost_sync_wake(state: *lai.lai_sync_state) void {
    _ = state;
    @panic("laihost_sync_wake");
}

var has_lai_acpi = false;

pub fn init_acpi() !void {
    if (rsdp_phys == null) {
        log(.info, "No RSDP registered... Looking for it ourselves", .{});
        rsdp_phys = locate_rsdp() orelse {
            log(.err, "Unable to locate RSDP ourselves", .{});
            return;
        };
    }

    log(.debug, "Using RSDP {} for acpi", .{rsdp_phys});

    rsdp = rsdp_phys.?.cast(*RSDP).get_writeback();

    log(.debug, "Revision: {d}", .{rsdp.revision});

    switch (rsdp.revision) {
        0 => parse_root_sdt(u32, rsdp.rsdt_addr),
        2 => parse_root_sdt(u64, rsdp.xsdt_addr),
        else => return error.UnknownACPIRevision,
    }

    lai.lai_set_acpi_revision(rsdp.revision);
    lai.lai_create_namespace();
    has_lai_acpi = true;
}
