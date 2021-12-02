pub const os = @import("../os.zig");
const std = @import("std");
const lib = @import("lib");

const log = lib.output.log.scoped(.{
    .prefix = "boot/stivale2",
    .filter = .info,
}).write;

const memory = os.memory;
const platform = os.platform;
const drivers = os.drivers;
const libalign = lib.util.libalign;
const builtin = std.builtin;

var display: os.drivers.output.single_mode_display.SingleModeDisplay = undefined;
var display_buffer: lib.graphics.single_buffer.SingleBuffer = undefined;

pub const putchar = os.kernel.logger.putch;

const MemmapEntry = packed struct {
    base: u64,
    length: u64,
    kind: u32,
    unused: u32,

    pub fn format(
        self: *const MemmapEntry,
        fmt: anytype,
    ) void {
        fmt("Base: 0x{0X}, length: 0x{0X}, type=0x{0X}", .{
            self.base,
            self.length,
            self.kind,
        });
    }
};

const Tag = packed struct {
    identifier: u64,
    next: ?*Tag,

    pub fn format(self: *const @This(), fmt: anytype) void {
        @compileError("Cannot format stivale2 tags");
    }
};

const Info = packed struct {
    bootloader_brand: [64]u8,
    bootloader_version: [64]u8,
    tags: ?*Tag,

    pub fn format(self: *const @This(), fmt: anytype) void {
        fmt(
            \\Bootloader info:
            \\    Bootloader brand: {s}
            \\    Bootloader version: {s}
            \\
        , .{
            @ptrCast([*:0]const u8, &self.bootloader_brand[0]),
            @ptrCast([*:0]const u8, &self.bootloader_version[0]),
        });
    }
};

const MemmapTag = packed struct {
    tag: Tag,
    entries: u64,

    pub fn get(self: *const @This()) []MemmapEntry {
        return @intToPtr([*]MemmapEntry, @ptrToInt(&self.entries) + 8)[0..self.entries];
    }

    pub fn format(
        self: *const @This(),
        fmt: anytype,
    ) void {
        fmt("{d} entries:\n", .{self.entries});
        for (self.get()) |ent| {
            fmt("    {}\n", .{ent});
        }
    }
};

const CmdLineTag = packed struct {
    tag: Tag,
    commandline: [*:0]u8,

    pub fn format(
        self: *const @This(),
        fmt: anytype,
    ) void {
        fmt("Commandline: {s}", .{self.commandline});
    }
};

const FramebufferTag = packed struct {
    tag: Tag,
    addr: u64,
    width: u16,
    height: u16,
    pitch: u16,
    bpp: u16,

    pub fn format(
        self: *const @This(),
        fmt: anytype,
    ) void {
        fmt("0x{X}, {d}x{d}, bpp={d}, pitch={d}", .{
            self.addr,
            self.width,
            self.height,
            self.bpp,
            self.pitch,
        });
    }
};

const RsdpTag = packed struct {
    tag: Tag,
    rsdp: u64,
};

const SMPTag = packed struct {
    tag: Tag,
    flags: u64,
    bsp_lapic_id: u32,
    _: u32,
    entries: u64,

    pub fn format(
        self: *const @This(),
        fmt: anytype,
    ) void {
        fmt("{} CPU(s): {}", .{ self.entries, self.get() });
    }

    pub fn get(self: *const @This()) []CoreInfo {
        return @intToPtr([*]CoreInfo, @ptrToInt(&self.entries) + 8)[0..self.entries];
    }
};

const CoreInfo = extern struct {
    acpi_proc_uid: u32,
    lapic_id: u32,
    target_stack: u64,
    goto_address: u64,
    argument: u64,
};

const Mmio32UartTag = packed struct {
    tag: Tag,
    uart_addr: u64,

    pub fn format(
        self: *const @This(),
        fmt: anytype,
    ) void {
        fmt("0x{X}", .{self.uart_addr});
    }
};

const Mmio32StatusUartTag = packed struct {
    tag: Tag,
    uart_addr: u64,
    uart_status: u64,
    status_mask: u32,
    status_value: u32,

    pub fn format(
        self: *const @This(),
        fmt: anytype,
    ) void {
        fmt("0x{X}, 0x{X}, (val & 0x{X}) == 0x{X}", .{
            self.uart_addr,
            self.uart_status,
            self.status_mask,
            self.status_value,
        });
    }
};

const DtbTag = packed struct {
    tag: Tag,
    addr: [*]u8,
    size: u64,

    pub fn slice(self: *const @This()) []u8 {
        return self.addr[0..self.size];
    }

    pub fn format(
        self: *const @This(),
        fmt: anytype,
    ) void {
        fmt("0x{X} bytes at 0x{X}", .{ self.size, @ptrToInt(self.addr) });
    }
};

const KernelFileTag = packed struct {
    tag: Tag,
    addr: u64,

    pub fn format(
        self: *const @This(),
        fmt: anytype,
    ) void {
        fmt("ELF at 0x{X}", .{self.addr});
    }
};

const ParsedInfo = struct {
    memmap: ?*MemmapTag = null,
    framebuffer: ?FramebufferTag = null,
    rsdp: ?platform.phys_ptr([*]u8) = null,
    smp: ?platform.phys_ptr(*SMPTag) = null,
    dtb: ?DtbTag = null,
    uart: ?Mmio32UartTag = null,
    uart_status: ?Mmio32StatusUartTag = null,
    kernel_file: ?KernelFileTag = null,

    pub fn valid(self: *const ParsedInfo) bool {
        if (self.memmap == null) return false;
        return true;
    }

    pub fn format(
        self: *const ParsedInfo,
        fmt: anytype,
    ) void {
        fmt(
            \\Parsed tag dump:
            \\  MemmapTag: {}
            \\  FramebufferTag: {}
            \\  RSDP: {}
            \\  SMP: {}
            \\  DTB: {}
            \\  UART: {}
            \\  UART with status: {}
            \\  Kernel file: {}
            \\
        , .{
            self.memmap.?,
            self.framebuffer,
            self.rsdp,
            self.smp,
            self.dtb,
            self.uart,
            self.uart_status,
            self.kernel_file,
        });
    }
};

fn consumePhysMem(ent: *const MemmapEntry) void {
    if (ent.kind == 1) {
        log(.info, "Consuming 0x{0X} to 0x{0X}", .{ ent.base, ent.base + ent.length });
        os.memory.pmm.consume(ent.base, ent.length);
    }
}

fn mapPhys(ent: *const MemmapEntry, context: *platform.paging.PagingContext) void {
    if (ent.kind != 1 and ent.kind != 0x1000) {
        return;
    }

    var new_ent = ent.*;

    new_ent.base = libalign.alignDown(u64, platform.paging.page_sizes[0], new_ent.base);
    // If there is nothing left of the entry
    if (new_ent.base >= ent.base + ent.length)
        return;

    new_ent.length = libalign.alignUp(u64, platform.paging.page_sizes[0], new_ent.length);
    if (new_ent.length == 0)
        return;

    log(.info, "Stivale: Mapping phys mem 0x{X} to 0x{X}", .{
        new_ent.base,
        new_ent.base + new_ent.length,
    });

    os.vital(paging.add_physical_mapping(.{
        .context = context,
        .phys = new_ent.base,
        .size = new_ent.length,
    }), "mapping physical stivale mem");
}

fn getPhysLimit(map: []const MemmapEntry) usize {
    if (map.len == 0) {
        @panic("No memmap!");
    }
    const ent = map[map.len - 1];
    return ent.base + ent.length;
}

fn initPaging() void {
    os.platform.paging.init();

    const base: usize = switch (os.platform.arch) {
        .aarch64 => 0xFFFF800000000000,
        .x86_64 => if (os.platform.paging.is_5levelpaging())
            @as(usize, 0xFF00000000000000)
        else
            0xFFFF800000000000,
        else => @panic("Phys base for platform unknown!"),
    };

    const context = &os.memory.paging.kernel_context;

    context.wb_virt_base = base;
    context.wc_virt_base = base;
    context.uc_virt_base = base;
    context.max_phys = 0x7F0000000000;
}

fn smpEntry(info_in: u64) callconv(.C) noreturn {
    const smp_info = platform.phys_ptr(*CoreInfo).from_int(info_in);
    const core_id = smp_info.get_writeback().argument;

    const cpu = &platform.smp.cpus[core_id];
    platform.thread.set_current_cpu(cpu);

    cpu.booted = true;
    platform.ap_init();

    cpu.bootstrap_tasking();
}

export fn stivale2Main(info_in: *Info) noreturn {
    platform.platform_early_init();

    log(.info, "Entry point reached", .{});

    var info = ParsedInfo{};

    var tag = info_in.tags;
    while (tag != null) : (tag = tag.?.next) {
        switch (tag.?.identifier) {
            0x2187F79E8612DE07 => info.memmap = @ptrCast(*MemmapTag, tag),
            0xE5E76A1B4597A781 => log(.info, "{}", .{@ptrCast(*CmdLineTag, tag)}),
            0x506461D2950408FA => info.framebuffer = @ptrCast(*FramebufferTag, tag).*,
            0x9E1786930A375E78 => info.rsdp = platform.phys_ptr([*]u8).from_int(@ptrCast(*RsdpTag, tag).rsdp),
            0x34D1D96339647025 => info.smp = platform.phys_ptr(*SMPTag).from_int(@ptrToInt(tag)),
            0xABB29BD49A2833FA => info.dtb = @ptrCast(*DtbTag, tag).*,
            0xB813F9B8DBC78797 => info.uart = @ptrCast(*Mmio32UartTag, tag).*,
            0xF77485DBFEB260F9 => info.uart_status = @ptrCast(*Mmio32StatusUartTag, tag).*,
            0xE599D90C2975584A => info.kernel_file = @ptrCast(*KernelFileTag, tag).*,
            0x566A7BED888E1407 => {}, // epoch
            0x274BD246C62BF7D1 => {}, // smbios
            0x4B6FE466AADE04CE => {}, // modules
            0x359D837855E3858C => {}, // firmware
            0xEE80847D01506C57 => {}, // kernel slide
            else => |ident| log(.warn, "Unknown struct tag identifier: 0x{0X}", .{ident}),
        }
    }

    initPaging();

    if (info.uart) |uart| {
        drivers.output.mmio_serial.register_mmio32_serial(uart.uart_addr);
        log(.info, "Registered UART", .{});
    }

    if (info.uart_status) |u| {
        drivers.output.mmio_serial.register_mmio32_status_serial(
            u.uart_addr,
            u.uart_status,
            u.status_mask,
            u.status_value,
        );
        log(.info, "Registered status UART", .{});
    }

    log(.debug, "Initializing framebuffer", .{});

    if (info.framebuffer) |fb| {
        const ptr = os.platform.phys_ptr([*]u8).from_int(fb.addr).get_writeback();
        display.init(
            ptr[0 .. @as(usize, fb.height) * @as(usize, fb.pitch)],
            fb.width,
            fb.height,
            fb.pitch,
            if (fb.bpp == 32) .rgbx else .rgb,
            null, // No invalidation needed for stivale2 framebuffer
        );
        drivers.output.vesa_log.use(&display.context.region);
        log(.debug, "Using non-buffered output", .{});
    } else {
        drivers.output.vga_log.register();
        log(.debug, "Using VGA output", .{});
    }

    log(.notice, "{}", .{info_in.*});
    log(.notice, "{}", .{info});

    if (!info.valid()) {
        @panic("Stivale2: Info not valid!");
    }

    if (info.dtb) |dtb| {
        os.vital(platform.devicetree.parse_dt(dtb.slice()), "parsing devicetree blob");
        log(.debug, "Stivale2: Parsed devicetree blob!", .{});
    }

    for (info.memmap.?.get()) |*ent| {
        consumePhysMem(ent);
    }

    if (info.kernel_file) |file| {
        const pp = os.platform.phys_ptr([*]u8).from_int(file.addr);
        os.kernel.debug.addDebugElf(pp.get_writeback());
    }

    var phys_high = getPhysLimit(info.memmap.?.get());
    // Eagerly map UART too, as it's initialized before exc handlers
    if (info.uart) |uart| {
        phys_high = std.math.max(phys_high, uart.uart_addr + 4);
    }
    if (info.uart_status) |uart| {
        phys_high = std.math.max(phys_high, uart.uart_addr + 4);
        phys_high = std.math.max(phys_high, uart.uart_status + 4);
    }

    // Attempt to speed up log scrolling using a buffer
    if (info.framebuffer) |_| {
        blk: {
            display_buffer.init(
                os.memory.pmm.phys_heap,
                &display.context.region,
            ) catch |err| {
                log(.err, "Stivale2: Error while allocating buffer: {e}", .{err});
                break :blk;
            };
            drivers.output.vesa_log.use(&display_buffer.buffered_region);
            log(.debug, "Stivale2: Using buffered output", .{});
        }
    }

    const page_size = platform.paging.page_sizes[0];

    phys_high += page_size - 1;
    phys_high &= ~(page_size - 1);

    var context = os.vital(memory.paging.bootstrapKernelPaging(), "bootstrapping kernel paging");

    os.vital(memory.paging.mapPhysmem(.{
        .context = &context,
        .map_limit = phys_high,
    }), "Mapping physmem");

    memory.paging.kernel_context = context;
    platform.thread.bsp_task.paging_context = &memory.paging.kernel_context;

    context.apply();

    // Use the write combining framebuffer
    if (info.framebuffer) |fb| {
        const ptr = os.platform.phys_ptr([*]u8).from_int(fb.addr).get_write_combining();
        display.context.region.bytes = ptr[0 .. @as(usize, fb.height) * @as(usize, fb.pitch)];
    }

    log(.debug, "Doing vmm", .{});

    const heap_base = memory.paging.kernel_context.make_heap_base();

    os.vital(memory.vmm.init(heap_base), "initializing vmm");

    log(.debug, "Doing scheduler", .{});

    os.thread.scheduler.init(&platform.thread.bsp_task);

    log(.debug, "Doing SMP", .{});

    if (info.smp) |smp| {
        var cpus = smp.get_writeback().get();

        platform.smp.init(cpus.len);
        cpus.len = platform.smp.cpus.len;

        const ap_init_stack_size = platform.thread.ap_init_stack_size;

        // Allocate stacks for all CPUs
        var bootstrap_stack_pool_sz = ap_init_stack_size * cpus.len;
        var stacks = os.vital(memory.pmm.allocPhys(bootstrap_stack_pool_sz), "no ap stacks");

        // Setup counter used for waiting
        @atomicStore(usize, &platform.smp.cpus_left, cpus.len - 1, .Release);

        // Initiate startup sequence for all cores in parallel
        for (cpus) |*cpu_info, i| {
            const cpu = &platform.smp.cpus[i];

            cpu.acpi_id = cpu_info.acpi_proc_uid;

            if (i == 0)
                continue;

            cpu.booted = false;

            // Boot it!
            const stack = stacks + ap_init_stack_size * i;

            cpu_info.argument = i;
            const stack_top = stack + ap_init_stack_size - 16;
            cpu_info.target_stack = memory.paging.physToWriteBackVirt(stack_top);
            @atomicStore(u64, &cpu_info.goto_address, @ptrToInt(smpEntry), .Release);
        }

        // Wait for the counter to become 0
        while (@atomicLoad(usize, &platform.smp.cpus_left, .Acquire) != 0) {
            platform.spin_hint();
        }

        // Free memory pool used for stacks. Unreachable for now
        memory.pmm.freePhys(stacks, bootstrap_stack_pool_sz);
        log(.debug, "All cores are ready for tasks!", .{});
    }

    if (info.rsdp) |rsdp| {
        log(.debug, "Registering rsdp: {}!", .{rsdp});
        platform.acpi.register_rsdp(rsdp);
    }

    os.vital(platform.platform_init(), "calling platform_init");

    os.kernel.kmain();
}
