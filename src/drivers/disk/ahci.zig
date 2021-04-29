const os = @import("root").os;
const std = @import("std");
const builtin = @import("builtin");

const log = os.log;

const pci = os.platform.pci;

const paging = os.memory.paging;
const pmm = os.memory.pmm;
const scheduler = os.thread.scheduler;
const page_size = os.platform.paging.page_sizes[0];

const abar_size = 0x1100;
const port_control_registers_size = 0x80;

const bf = os.lib.bitfields;
const libalign = os.lib.libalign;

const Port = packed struct {
    command_list_base: [2]u32,
    fis_base: [2]u32,
    interrupt_status: u32,
    interrupt_enable: u32,
    command_status: extern union {
        raw: u32,

        start: bf.boolean(u32, 0),
        recv_enable: bf.boolean(u32, 4),
        fis_recv_running: bf.boolean(u32, 14),
        command_list_running: bf.boolean(u32, 15),
    },
    reserved_0x1C: u32,
    task_file_data: extern union {
        raw: u32,

        transfer_requested: bf.boolean(u32, 3),
        interface_busy: bf.boolean(u32, 7),
    },
    signature: u32,
    sata_status: u32,
    sata_control: u32,
    sata_error: u32,
    sata_active: u32,
    command_issue: u32,
    sata_notification: u32,
    fis_switching_control: u32,
    device_sleep: u32,
    reserved_0x48: [0x70 - 0x48]u8,
    vendor_0x70: [0x80 - 0x70]u8,

    pub fn command_headers(self: *const volatile @This()) *volatile [32]CommandTableHeader {
        const addr = read_u64(&self.command_list_base);
        return &os.platform.phys_ptr(*volatile CommandList).from_int(addr).get_uncached().command_headers;
    }

    pub fn start_command_engine(self: *volatile @This()) void {
        os.log("AHCI: Starting command engine for port at 0x{X}\n", .{@ptrToInt(self)});

        self.wait_ready();

        self.command_status.start.write(false);
        self.command_status.recv_enable.write(false);

        while (self.command_status.command_list_running.read() or self.command_status.fis_recv_running.read())
            scheduler.yield();

        self.command_status.recv_enable.write(true);
        self.command_status.start.write(true);
    }

    pub fn stop_command_engine(self: *volatile @This()) void {
        os.log("AHCI: Stopping command engine for port at 0x{X}\n", .{@ptrToInt(self)});
        self.command_status.start.write(false);

        while (self.command_status.command_list_running.read())
            scheduler.yield();

        self.command_status.recv_enable.write(false);

        while (self.command_status.fis_recv_running.read())
            scheduler.yield();
    }

    pub fn wait_ready(self: *volatile @This()) void {
        while (self.task_file_data.transfer_requested.read() or self.task_file_data.interface_busy.read())
            scheduler.yield();
    }

    pub fn issue_commands(self: *volatile @This(), slot_bits: u32) void {
        log("AHCI: Sending {} command(s) to port 0x{X}\n", .{ @popCount(u32, slot_bits), @ptrToInt(self) });

        self.wait_ready();

        self.command_issue |= slot_bits;

        while ((self.command_issue & slot_bits) != 0)
            scheduler.yield();
    }

    pub fn command_header(self: *const volatile @This(), slot: u5) *volatile CommandTableHeader {
        return &self.command_headers()[slot];
    }

    pub fn command_table(self: *const volatile @This(), slot: u5) *volatile CommandTable {
        return self.command_header(slot).table();
    }

    pub fn get_fis(self: *volatile @This(), slot: u5) *volatile CommandFis {
        return &self.command_table(slot).command_fis;
    }

    pub fn make_h2d(self: *volatile @This(), slot: u5) *volatile FisH2D {
        const fis = &self.get_fis(slot).h2d;
        fis.fis_type = 0x27;
        return fis;
    }

    pub fn prd(self: *volatile @This(), slot: u5, prd_idx: usize) *volatile PRD {
        return &self.command_table(slot).prds[prd_idx];
    }

    pub fn buffer(self: *volatile @This(), slot: u5, prd_idx: usize) []u8 {
        const prd_ptr = self.prd(slot, 0);
        const buf_addr = read_u64(&prd_ptr.data_base_addr);
        const buf_size = @as(usize, prd_ptr.sizem1) + 1;
        return os.platform.phys_slice(u8).init(buf_addr, buf_size).to_slice_writeback();
    }

    pub fn read_single_sector(self: *volatile @This(), slot: u5) void {
        self.issue_commands(1 << slot);
    }
};

fn write_u64(mmio: anytype, value: u64) void {
    mmio[0] = @truncate(u32, value);
    mmio[1] = @truncate(u32, value >> 32);
}

fn read_u64(mmio: anytype) u64 {
    return @as(u64, mmio[0]) | (@as(u64, mmio[1]) << 32);
}

comptime {
    std.debug.assert(@sizeOf(Port) == 0x80);
}

const ABAR = struct {
    hba_capabilities: u32,
    global_hba_control: u32,
    interrupt_status: u32,
    ports_implemented: u32,
    version: extern union {
        value: u32,

        major: bf.bitfield(u32, 16, 16),
        minor_high: bf.bitfield(u32, 8, 8),
        minor_low: bf.bitfield(u32, 0, 8),

        pub fn format(self: *const @This(), fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print("{}.{}", .{ self.major.read(), self.minor_high.read() });
            if (self.minor_low.read() != 0)
                try writer.print(".{}", .{self.minor_low.read()});
        }

        comptime {
            std.debug.assert(@sizeOf(@This()) == 4);
            std.debug.assert(@bitSizeOf(@This()) == 32);
        }
    },
    command_completion_coalescing_control: u32,
    command_completion_coalescing_port: u32,
    enclosure_managment_location: u32,
    enclosure_managment_control: u32,
    hba_capabilities_extended: u32,
    bios_handoff: extern union {
        value: u32,
        bios_owned: bf.boolean(u32, 4),
        os_owned: bf.boolean(u32, 1),
        bios_busy: bf.boolean(u32, 0),

        fn set_handoff(self: *volatile @This()) void {
            self.os_owned.write(true);
        }

        fn check_handoff(self: *volatile @This()) bool {
            if (self.bios_owned.read())
                return false;

            if (self.bios_busy.read())
                return false;

            if (self.os_owned.read())
                return true;

            return false;
        }

        fn try_claim(self: *volatile @This()) bool {
            self.set_handoff();
            return self.check_handoff();
        }

        comptime {
            std.debug.assert(@sizeOf(@This()) == 4);
            std.debug.assert(@bitSizeOf(@This()) == 32);
        }
    },
    reserved_0x2C: u32,
    reserved_0x30: [0xA0 - 0x30]u8,
    vendor_0xA0: [0x100 - 0xA0]u8,
    ports: [32]Port,
};

comptime {
    std.debug.assert(@sizeOf(ABAR) == 0x1100);
}

fn claim_controller(abar: *volatile ABAR) void {
    {
        const version = abar.version;
        log("AHCI: Version: {}\n", .{version});

        if (version.major.read() < 1 or version.minor_high.read() < 2) {
            log("AHCI: Handoff not supported (version)\n", .{});
            return;
        }
    }

    if (abar.hba_capabilities_extended & 1 == 0) {
        log("AHCI: Handoff not supported (capabilities)\n", .{});
        return;
    }

    while (!abar.bios_handoff.try_claim()) {
        scheduler.yield();
    }

    log("AHCI: Got handoff!\n", .{});
}

const sata_port_type = enum {
    ata,
    atapi,
    semb,
    pm,
};

const CommandTableHeader = packed struct {
    command_fis_length: u5,
    atapi: u1,
    write: u1,
    prefetchable: u1,

    sata_reset_control: u1,
    bist: u1,
    clear: u1,
    _res1_3: u1,
    pmp: u4,

    pdrt_count: u16,
    command_table_byte_size: u32,
    command_table_addr: [2]u32,
    reserved: [4]u32,

    pub fn table(self: *volatile @This()) *volatile CommandTable {
        const addr = read_u64(&self.command_table_addr);
        return os.platform.phys_ptr(*volatile CommandTable).from_int(addr).get_uncached();
    }
};

comptime {
    std.debug.assert(@sizeOf(CommandTableHeader) == 0x20);
}

const CommandList = struct {
    command_headers: [32]CommandTableHeader,
};

const RecvFis = struct {
    dma_setup: [0x1C]u8,
    _res1C: [0x20 - 0x1C]u8,

    pio_setup: [0x14]u8,
    _res34: [0x40 - 0x34]u8,

    d2h_register: [0x14]u8,
    _res54: [0x58 - 0x54]u8,

    set_device_bits: [8]u8,

    unknown_fis: [0x40]u8,
    _resA0: [0x100 - 0xA0]u8,
};

comptime {
    std.debug.assert(@byteOffsetOf(RecvFis, "dma_setup") == 0);
    std.debug.assert(@byteOffsetOf(RecvFis, "pio_setup") == 0x20);
    std.debug.assert(@byteOffsetOf(RecvFis, "d2h_register") == 0x40);
    std.debug.assert(@byteOffsetOf(RecvFis, "set_device_bits") == 0x58);
    std.debug.assert(@byteOffsetOf(RecvFis, "unknown_fis") == 0x60);
    std.debug.assert(@sizeOf(RecvFis) == 0x100);
}

const PRD = packed struct {
    data_base_addr: [2]u32,
    _res08: u32,
    sizem1: u22,
    _res10_22: u9,
    completion_interrupt: u1,
};

comptime {
    std.debug.assert(@sizeOf(PRD) == 0x10);
}

const FisH2D = packed struct {
    fis_type: u8,
    pmport: u4,
    _res1_4: u3,
    c: u1,

    command: u8,
    feature_low: u8,

    lba_low: u24,
    device: u8,

    lba_high: u24,
    feature_high: u8,

    count: u16,
    icc: u8,
    control: u8,
};

comptime {
    std.debug.assert(@byteOffsetOf(FisH2D, "command") == 2);
}

const CommandFis = extern union {
    bytes: [0x40]u8,
    h2d: FisH2D,
    //d2h: FisD2H,
};

const CommandTable = struct {
    command_fis: CommandFis,
    atapi_command: [0x10]u8,
    _res50: [0x80 - 0x50]u8,
    // TODO: Maybe more(?)
    // First buffer should always be pointing to a single preallocated page
    // when this command table is unused. Make sure to restore it if you overwrite it
    prds: [8]PRD,
};

const ReadOrWrite = enum {
    Read,
    Write,
};

// Our own structure for keeping track of everything we need for a port
const PortState = struct {
    mmio: *volatile Port = undefined,
    num_sectors: usize = undefined,
    sector_size: usize = 512,
    port_type: sata_port_type = undefined,

    pub fn init(port: *volatile Port) !PortState {
        var result: PortState = .{};
        result.mmio = port;
        result.port_type =
            switch(result.mmio.signature) {
                0x00000101 => .ata,
                //0xEB140101 => .atapi, // Drop atapi for now
                else => return error.UnknownSignature,
            };

        result.mmio.stop_command_engine();

        try result.setup_command_headers();

        try result.setup_prdts();

        result.mmio.start_command_engine();

        try result.identify();

        return result;
    }

    fn setup_command_headers(self: *@This()) !void {
        const port_io_size = @sizeOf(CommandList) + @sizeOf(RecvFis);

        const commands_phys = try pmm.alloc_phys(port_io_size);
        const fis_phys = commands_phys + @sizeOf(CommandList);
        @memset(os.platform.phys_ptr([*]u8).from_int(commands_phys).get_uncached(), 0, port_io_size);
        write_u64(&self.mmio.command_list_base, commands_phys);
        write_u64(&self.mmio.fis_base, fis_phys);
    }

    fn setup_prdts(self: *@This()) !void {
        var current_table_addr: usize = undefined;
        var reamining_table_size: usize = 0;
        for (self.mmio.command_headers()) |*header| {
            if (reamining_table_size < @sizeOf(CommandTable)) {
                reamining_table_size = page_size;
                current_table_addr = try pmm.alloc_phys(page_size);
                @memset(os.platform.phys_ptr([*]u8).from_int(current_table_addr).get_uncached(), 0, page_size);
            }

            write_u64(&header.command_table_addr, current_table_addr);
            header.pdrt_count = 1;
            header.command_fis_length = @sizeOf(FisH2D) / @sizeOf(u32);
            header.atapi = if (self.port_type == .atapi) 1 else 0;
            current_table_addr += @sizeOf(CommandTable);
            reamining_table_size -= @sizeOf(CommandTable);

            // First PRD is just a small preallocated single page buffer
            const buf = try pmm.alloc_phys(page_size);
            @memset(os.platform.phys_ptr([*]u8).from_int(buf).get_uncached(), 0, page_size);
            write_u64(&header.table().prds[0].data_base_addr, buf);
            header.table().prds[0].sizem1 = page_size - 1;
        }
    }

    fn identify_command(self: *@This()) u8 {
        return switch (self.port_type) {
            .ata => 0xEC,
            .atapi => 0xA1,
            else => unreachable,
        };
    }

    fn identify(self: *@This()) !void {
        //log("AHCI: Identifying drive...\n", .{});

        const identify_fis = self.mmio.make_h2d(0);

        identify_fis.command = self.identify_command();

        identify_fis.c = 1;
        identify_fis.device = 0;

        self.mmio.issue_commands(1);

        const buf = self.mmio.buffer(0, 0);

        //os.hexdump(buf[0..256]);

        const data_valid = std.mem.readIntLittle(u16, buf[212..][0..2]);

        if(data_valid & (1 << 15) == 0 and data_valid & (1 << 14) != 0 and data_valid & (1 << 12) != 0)
            self.sector_size = std.mem.readIntLittle(u32, buf[234..][0..4]);

        self.num_sectors = std.mem.readIntLittle(u64, buf[200..][0..8]);
        if(self.num_sectors == 0)
            self.num_sectors = std.mem.readIntLittle(u32, buf[120..][0..4]);

        if(self.num_sectors == 0)
            return error.NoSectors;

        log("AHCI: Disk has 0x{X} sectors of size {}\n", .{self.num_sectors, self.sector_size});
    }

    fn issue_command_on_port(self: *@This(), command_slot: u5) void {
        // TODO: Call this from command slot task and
        // make this dispatch work to the port task
        self.mmio.issue_commands(@as(u32, 1) << command_slot);
    }

    fn finalize_io(self: *@This(), command_slot: u5, lba: u48, sector_count: u16, mode: ReadOrWrite) void {
        const fis = self.mmio.make_h2d(0);

        fis.command =
            switch (self.port_type) {
            .ata => switch(mode) {
                .Read => @as(u8, 0x25),
                .Write => 0x35,
            },
            else => unreachable,
        };

        fis.device = 0xA0 | (1 << 6);
        fis.control = 0x08;

        fis.lba_low  = @truncate(u24, lba);
        fis.lba_high = @truncate(u24, lba >> 24);

        fis.count = sector_count;

        self.issue_command_on_port(command_slot);
    }

    // All the following functions will sooner or later be moved out into a general
    // block dev interface, and this will just have a simple dma interface instead.
    pub fn offset_to_sector(self: *@This(), offset: usize) u48 {
        return @intCast(u48, offset / self.sector_size);
    }

    fn do_small_write(self: *@This(), command_slot: u5, buffer: []const u8, lba: u48, offset: usize) void {
        self.mmio.command_header(command_slot).pdrt_count = 1;

        // Read the shit we're not going to overwite
        self.finalize_io(command_slot, lba, 1, .Read);

        // Overwrite what we want to buffer
        for(buffer) |b, i| {
            self.mmio.buffer(command_slot, 0)[offset + i] = b;
        }

        // Write buffer to disk
        self.finalize_io(command_slot, lba, 1, .Write);
    }

    fn do_small_read(self: *@This(), command_slot: u5, buffer: []u8, lba: u48, offset: usize) void {
        self.finalize_io(command_slot, lba, 1, .Read);
        for(buffer) |*b, i|
            b.* = self.mmio.buffer(command_slot, 0)[offset + i];
    }

    fn do_large_write(self: *@This(), command_slot: u5, buffer: []const u8, lba: u48) void {
        for(buffer[0..self.sector_size]) |b, i|
            self.mmio.buffer(command_slot, 0)[i] = b;
        self.finalize_io(command_slot, lba, 1, .Write);
    }

    fn do_large_read(self: *@This(), command_slot: u5, buffer: []u8, lba: u48) void {
        self.finalize_io(command_slot, lba, 1, .Read);
        for(buffer[0..self.sector_size]) |*b, i|
            b.* = self.mmio.buffer(command_slot, 0)[i];
    }

    fn iterate_byte_sectors(
        self: *@This(),
        command_slot: u5,
        buffer_in: anytype,
        disk_offset_in: usize,
        small_callback: anytype,
        large_callback: anytype,
    ) void {
        if(buffer_in.len == 0)
            return;

        self.mmio.command_header(command_slot).pdrt_count = 1;

        var first_sector = self.offset_to_sector(disk_offset_in);
        const last_sector = self.offset_to_sector(disk_offset_in + buffer_in.len - 1);

        if(first_sector == last_sector) {
            small_callback(self, command_slot, buffer_in, first_sector, disk_offset_in % self.sector_size);
            return;
        }

        var disk_offset = disk_offset_in;
        var buffer = buffer_in;

        // We need to preserve data on the first sector
        if(!libalign.is_aligned(usize, self.sector_size, disk_offset)) {
            const step = libalign.align_up(usize, self.sector_size, disk_offset) - disk_offset;

            small_callback(self, command_slot, buffer[0..step], first_sector, self.sector_size - step);

            buffer.ptr += step;
            buffer.len -= step;
            disk_offset += step;
            first_sector += 1;
        }

        // Now we're sector aligned, we can do the transfer sector by sector
        // TODO: make this faster, doing multiple sectors at a time
        while(buffer.len > self.sector_size) {
            os.log("Doing entire sector {}\n", .{first_sector});

            large_callback(self, command_slot, buffer, first_sector);

            buffer.ptr += self.sector_size;
            buffer.len -= self.sector_size;
            first_sector += 1;
        }

        if(buffer.len == 0)
            return;

        os.log("Doing last partial sector {}\n", .{first_sector});
        // Last sector, partial
        small_callback(self, command_slot, buffer, first_sector, 0);
    }

    pub fn do_io_bytes_write(self: *@This(), command_slot: u5, buffer: []const u8, disk_offset: usize) void {
        self.iterate_byte_sectors(command_slot, buffer, disk_offset, do_small_write, do_large_write);
    }

    pub fn do_io_bytes_read(self: *@This(), command_slot: u5, buffer: []u8, disk_offset: usize) void {
        self.iterate_byte_sectors(command_slot, buffer, disk_offset, do_small_read, do_large_read);
    }
};

comptime {
    std.debug.assert(@sizeOf(CommandTable) == 0x100);
}

fn command(port: *volatile Port, slot: u5) void {}

fn command_with_buffer(port: *volatile Port, slot: u5, buf: usize, bufsize: usize) void {
    const header = &port.command_headers()[slot];
    //const oldbuf = header.;
    //const oldsize = ;
}

var test_buf: [4096]u8 = undefined;

fn sata_port_task(port_type: sata_port_type, port: *volatile Port) !void {
    switch (port_type) {
        .ata, .atapi => {},
        else => return,
    }

    log("AHCI: {s} task started for port at 0x{X}\n", .{ @tagName(port_type), @ptrToInt(port) });

    var port_state = try PortState.init(port);

    // Put 0x204 'x's across 3 sectors if sector size is 0x200
    //port_state.do_io_bytes_write(0, "x" ** 0x204, port_state.sector_size - 2);
    //port_state.finalize_io(0, 0, 3, .Read);
    //os.hexdump(port_state.mmio.buffer(0, 0)[port_state.sector_size - 0x10..port_state.sector_size * 2 + 0x10]);

    // Read first disk sector
    port_state.finalize_io(0, 0, 1, .Read);
    os.hexdump(port_state.mmio.buffer(0, 0)[0..port_state.sector_size]);

    // Read first sector into buffer
    //port_state.do_io_bytes_read(0, test_buf[0..512], 0);
    //os.hexdump(test_buf[0..512]);
}

fn controller_task(abar: *volatile ABAR) !void {
    claim_controller(abar);

    log("AHCI: Claimed controller.\n", .{});

    const ports_implemented = abar.ports_implemented;

    for (abar.ports) |*port, i| {
        if ((ports_implemented >> @intCast(u5, i)) & 1 == 0)
            continue;

        {
            const sata_status = port.sata_status;

            {
                const com_status = sata_status & 0xF;

                if (com_status == 0)
                    continue;

                if (com_status != 3) {
                    log("AHCI: Warning: Unknown port com_status: {}\n", .{com_status});
                    continue;
                }
            }

            {
                const ipm_status = (sata_status >> 8) & 0xF;

                if (ipm_status != 1) {
                    log("AHCI: Warning: Device sleeping: {}\n", .{ipm_status});
                    continue;
                }
            }
        }

        switch (port.signature) {
            0x00000101 => try scheduler.spawn_task(sata_port_task, .{ .ata, port }),
            //0xEB140101 => try scheduler.spawn_task(sata_port_task, .{.atapi, port}),
            0xC33C0101, 0x96690101 => {
                log("AHCI: Known TODO port signature: 0x{X}\n", .{port.signature});
                //scheduler.spawn_task(sata_port_task, .{.semb,   port})
                //scheduler.spawn_task(sata_port_task, .{.pm,     port})
            },
            else => {
                log("AHCI: Unknown port signature: 0x{X}\n", .{port.signature});
                return;
            },
        }
    }
}

pub fn register_controller(addr: pci.Addr) void {
    // Busty master bit
    addr.command().write(addr.command().read() | 0x6);

    const abar = os.platform.phys_ptr(*volatile ABAR).from_int(addr.barinfo(5).phy & 0xFFFFF000).get_uncached();

    const cap = abar.hba_capabilities;

    if ((cap & (1 << 31)) == 0) {
        log("AHCI: Controller is 32 bit only, ignoring.\n", .{});
        return;
    }

    if (abar.global_hba_control & (1 << 31) == 0) {
        log("AHCI: AE not set!\n", .{});
        return;
    }

    scheduler.spawn_task(controller_task, .{abar}) catch |err| {
        log("AHCI: Failed to make controller task: {s}\n", .{@errorName(err)});
    };
}
