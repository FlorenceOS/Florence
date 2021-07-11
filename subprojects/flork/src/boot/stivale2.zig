pub const preamble = @import("../preamble.zig");
usingnamespace preamble;

const memory = os.memory;
const platform = os.platform;
const drivers = os.drivers;
const libalign = lib.util.libalign;
const builtin = std.builtin;

var display: os.drivers.output.single_mode_display.SingleModeDisplay = undefined;
var display_buffer: lib.graphics.single_buffer.SingleBuffer = undefined;

const MemmapEntry = packed struct {
    base: u64,
    length: u64,
    kind: u32,
    unused: u32,

    pub fn format(
        self: *const MemmapEntry,
        fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("Base: 0x{X}, length: 0x{X}, type=0x{X}", .{
            self.base,
            self.length,
            self.kind,
        });
    }
};

const Tag = packed struct {
    identifier: u64,
    next: ?*Tag,

    pub fn format(
        self: *const @This(),
        fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("Identifier: 0x{X:0>16}", .{self.identifier});
    }
};

const Info = packed struct {
    bootloader_brand: [64]u8,
    bootloader_version: [64]u8,
    tags: ?*Tag,
};

const MemmapTag = packed struct {
    tag: Tag,
    entries: u64,

    pub fn get(self: *const @This()) []MemmapEntry {
        return @intToPtr([*]MemmapEntry, @ptrToInt(&self.entries) + 8)[0..self.entries];
    }

    pub fn format(
        self: *const @This(),
        fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{} entries:\n", .{self.entries});
        for (self.get()) |ent| {
            try writer.print("    {}\n", .{ent});
        }
    }
};

const CmdLineTag = packed struct {
    tag: Tag,
    commandline: [*:0]u8,

    pub fn format(
        self: *const @This(),
        fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("Commandline: {s}", .{self.commandline});
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
        fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("0x{X}, {}x{}, bpp={}, pitch={}", .{
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

    pub fn format(
        self: *const @This(),
        fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("0x{X}", .{self.rsdp});
    }
};

const SMPTag = packed struct {
    tag: Tag,
    flags: u64,
    bsp_lapic_id: u32,
    _: u32,
    entries: u64,

    pub fn format(
        self: *const @This(),
        fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{} CPU(s): {}", .{ self.entries, self.get() });
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
        fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("0x{X}", .{self.uart_addr});
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
        fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("0x{X}, 0x{X}, (val & 0x{X}) == 0x{X}", .{
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
        fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("0x{X} bytes at 0x{X}", .{ self.size, @ptrToInt(self.addr) });
    }
};

const ParsedInfo = struct {
    memmap: ?*MemmapTag = null,
    framebuffer: ?FramebufferTag = null,
    rsdp: ?u64 = null,
    smp: ?platform.phys_ptr(*SMPTag) = null,
    dtb: ?DtbTag = null,
    uart: ?Mmio32UartTag = null,
    uart_status: ?Mmio32StatusUartTag = null,

    pub fn valid(self: *const ParsedInfo) bool {
        if (self.memmap == null) return false;
        return true;
    }

    pub fn format(
        self: *const ParsedInfo,
        fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print(
            \\Parsed stivale2 tags:
            \\  MemmapTag: {}
            \\  FramebufferTag: {}
            \\  RSDP: {}
            \\  SMP: {}
            \\  DTB: {}
            \\  UART: {}
            \\  UART with status: {}
            \\
            \\
        , .{
            self.memmap,
            self.framebuffer,
            self.rsdp,
            self.smp,
            self.dtb,
            self.uart,
            self.uart_status,
        });
    }
};

fn consumePhysMem(ent: *const MemmapEntry) void {
    if (ent.kind == 1) {
        os.log("Stivale: Consuming 0x{X} to 0x{X}\n", .{ ent.base, ent.base + ent.length });
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

    os.log("Stivale: Mapping phys mem 0x{X} to 0x{X}\n", .{
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

    os.log("Stivale2: Boot!\n", .{});

    var info = ParsedInfo{};

    var tag = info_in.tags;
    while (tag != null) : (tag = tag.?.next) {
        switch (tag.?.identifier) {
            0x2187f79e8612de07 => info.memmap = @ptrCast(*MemmapTag, tag),
            0xe5e76a1b4597a781 => os.log("{s}\n", .{@ptrCast(*CmdLineTag, tag)}),
            0x506461d2950408fa => info.framebuffer = @ptrCast(*FramebufferTag, tag).*,
            0x9e1786930a375e78 => info.rsdp = @ptrCast(*RsdpTag, tag).rsdp,
            0x34d1d96339647025 => info.smp = platform.phys_ptr(*SMPTag).from_int(@ptrToInt(tag)),
            0xabb29bd49a2833fa => info.dtb = @ptrCast(*DtbTag, tag).*,
            0xb813f9b8dbc78797 => info.uart = @ptrCast(*Mmio32UartTag, tag).*,
            0xf77485dbfeb260f9 => info.uart_status = @ptrCast(*Mmio32StatusUartTag, tag).*,
            else => {
                os.log("Unknown stivale2 tag identifier: 0x{X:0>16}\n", .{tag.?.identifier});
            },
        }
    }

    initPaging();

    if (info.uart) |uart| {
        drivers.output.mmio_serial.register_mmio32_serial(uart.uart_addr);
        os.log("Stivale2: Registered UART\n", .{});
    }

    if (info.uart_status) |u| {
        drivers.output.mmio_serial.register_mmio32_status_serial(
            u.uart_addr,
            u.uart_status,
            u.status_mask,
            u.status_value,
        );
        os.log("Stivale2: Registered status UART\n", .{});
    }

    os.log("Doing framebuffer\n", .{});

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
        os.log("Stivale2: Using non-buffered output\n", .{});
    } else {
        drivers.output.vga_log.register();
    }

    os.log(
        \\Bootloader: {s}
        \\Bootloader version: {s}
        \\{}
    , .{ info_in.bootloader_brand, info_in.bootloader_version, info });

    if (!info.valid()) {
        @panic("Stivale2: Info not valid!\n");
    }

    if (info.dtb) |dtb| {
        os.vital(platform.devicetree.parse_dt(dtb.slice()), "parsing devicetree blob");
        os.log("Stivale2: Parsed devicetree blob!\n", .{});
    }

    for (info.memmap.?.get()) |*ent| {
        consumePhysMem(ent);
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
            display_buffer.init(&display.context.region) catch |err| {
                os.log("Stivale2: Error while allocating buffer: {}\n", .{err});
                break :blk;
            };
            drivers.output.vesa_log.use(&display_buffer.buffered_region);
            os.log("Stivale2: Using buffered output\n", .{});
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

    os.log("Doing vmm\n", .{});

    const heap_base = memory.paging.kernel_context.make_heap_base();

    os.vital(memory.vmm.init(heap_base), "initializing vmm");

    os.log("Doing scheduler\n", .{});

    os.thread.scheduler.init(&platform.thread.bsp_task);

    os.log("Doing SMP\n", .{});

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
        os.log("All cores are ready for tasks!\n", .{});
    }

    if (info.rsdp) |rsdp| {
        os.log("Registering rsdp: 0x{X}!\n", .{rsdp});
        platform.acpi.register_rsdp(rsdp);
    }

    os.vital(platform.platform_init(), "calling platform_init");

    os.kernel.kmain();
}
