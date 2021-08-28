usingnamespace @import("root").preamble;

const num_rx_desc = 32;
const num_tx_desc = 8;

const rx_block_size = 2048;

const Register = extern enum(u16) {
    ctrl = 0x0000,
    status = 0x0008,
    eeprom = 0x0014,
    ctrl_ex = 0x0018,
    imask = 0x00D0,
    rctrl = 0x0100,

    tctrl = 0x0400,
    tipg = 0x0410,

    rx_descs_low = 0x2800,
    rx_descs_high = 0x2804,
    rx_descs_len = 0x2808,
    rx_descs_head = 0x2810,
    rx_descs_tail = 0x2818,

    rdtr = 0x2820,
    radv = 0x282C,

    rsrpd = 0x2C00,

    tx_descs_low = 0x3800,
    tx_descs_high = 0x3804,
    tx_descs_len = 0x3808,
    tx_descs_head = 0x3810,
    tx_descs_tail = 0x3818,

    rxdctl = 0x3828,

    mac0 = 0x5400,
    mac1 = 0x5401,
    mac2 = 0x5402,
    mac3 = 0x5403,
    mac4 = 0x5404,
    mac5 = 0x5405,
};

const RXDesc = packed struct {
    addr: u64,
    length: u16,
    checksum: u16,
    status: u8,
    errors: u8,
    special: u16,
};

const TXDesc = packed struct {
    addr: u64,
    length: u16,
    cso: u8,
    cmd: u8,
    status: u8,
    css: u8,
    special: u16,
};

const Controller = struct {
    base_addr: u64,
    advertises_eeprom: bool = false,
    mac: [6]u8 = undefined,
    rx_descs: *[num_rx_desc]RXDesc = undefined,
    tx_descs: *[num_tx_desc]TXDesc = undefined,

    fn read(self: *@This(), comptime t: type, reg: Register) t {
        return os.platform.phys_ptr(*t).from_int(self.base_addr + @intCast(u64, @enumToInt(reg))).get_uncached().*;
    }

    fn write(self: *@This(), comptime t: type, reg: Register, value: u32) void {
        os.platform.phys_ptr(*t).from_int(self.base_addr + @intCast(u64, @enumToInt(reg))).get_uncached().* = value;
    }

    fn detectEeprom(self: *@This()) void {
        self.write(u32, .eeprom, 0x1);

        var i: usize = 0;
        while (i < 1000) : (i += 1) {
            const val = self.read(u32, .eeprom);
            if ((val & 0x10) != 0) {
                self.advertises_eeprom = true;
                return;
            }
        }
    }

    fn readEeprom(self: *@This(), addr: u8) u16 {
        const mask: u32 = if (self.advertises_eeprom)
            (1 << 4)
        else
            (1 << 1);

        const addr_shift: u5 = if (self.advertises_eeprom)
            8
        else
            2;

        self.write(u32, .eeprom, 1 | (@as(u32, addr) << addr_shift));
        while (true) {
            const val = self.read(u32, .eeprom);
            if ((val & mask) == 0) continue;

            return @truncate(u16, val >> 16);
        }
    }

    fn readMAC(self: *@This()) void {
        if (self.advertises_eeprom) {
            const v0 = self.readEeprom(0);
            const v1 = self.readEeprom(1);
            const v2 = self.readEeprom(2);

            self.mac = [_]u8{
                @truncate(u8, v0),
                @truncate(u8, v0 >> 8),
                @truncate(u8, v1),
                @truncate(u8, v1 >> 8),
                @truncate(u8, v2),
                @truncate(u8, v2 >> 8),
            };
        } else {
            self.mac = [_]u8{
                self.read(u8, .mac0),
                self.read(u8, .mac1),
                self.read(u8, .mac2),
                self.read(u8, .mac3),
                self.read(u8, .mac4),
                self.read(u8, .mac5),
            };
        }
    }

    fn setupRX(self: *@This()) !void {
        const desc_bytes = @sizeOf(RXDesc) * num_rx_desc;
        const base_phys = try os.memory.pmm.allocPhys(desc_bytes);
        self.rx_descs = os.platform.phys_ptr([*]RXDesc).from_int(base_phys).get_uncached()[0..num_rx_desc];

        for (self.rx_descs) |*desc| {
            desc.addr = try os.memory.pmm.allocPhys(rx_block_size + 16);
            desc.status = 0;
        }

        os.log("E1000: RX list prepared\n", .{});

        self.write(u32, .rx_descs_low, @truncate(u32, base_phys));
        self.write(u32, .rx_descs_high, @truncate(u32, base_phys >> 32));

        self.write(u32, .rx_descs_len, desc_bytes);
        self.write(u32, .rx_descs_head, 0);
        self.write(u32, .rx_descs_tail, num_rx_desc - 1);

        // zig fmt: off
        self.write(u32, .rctrl, 0
            | (1 << 1) // EN, reciever ENable
            | (1 << 2) // SBP, Store Bad Packets
            | (1 << 3) // UPE, Unicast Promiscuous Enabled
            | (1 << 4) // MPE, Multicast Promiscuous Enabled
            | (0 << 6) // LBM_NONE, No loopback
            | (0 << 8) // RDMTS_HALF, free buffer threshold is HALF of RDLEN
            | (1 << 15) // BAM, Broadcast Accept Mode
            | (1 << 26) // SECRC, Strip Ethernet CRC
            | switch (rx_block_size) { // BSIZE
                256 => (3 << 16),
                512 => (2 << 16),
                1024 => (1 << 16),
                2048 => (0 << 16),
                4096 => (3 << 16) | (1 << 25),
                8192 => (2 << 16) | (1 << 25),
                16384 => (1 << 16) | (1 << 25),
                else => @compileError("Bad rx_block_size"),
            }
        );
        // zig fmt: on

        os.log("E1000: RX set up\n", .{});
    }

    fn setupTX(self: *@This()) !void {
        const desc_bytes = @sizeOf(TXDesc) * num_tx_desc;
        const base_phys = try os.memory.pmm.allocPhys(desc_bytes);
        self.tx_descs = os.platform.phys_ptr([*]TXDesc).from_int(base_phys).get_uncached()[0..num_tx_desc];

        for (self.tx_descs) |*desc| {
            desc.addr = 0;
            desc.cmd = 0;
            desc.status = (1 << 0); // TSTA_DD
        }

        os.log("E1000: TX list prepared\n", .{});

        self.write(u32, .tx_descs_low, @truncate(u32, base_phys));
        self.write(u32, .tx_descs_high, @truncate(u32, base_phys >> 32));

        self.write(u32, .tx_descs_len, desc_bytes);

        self.write(u32, .tx_descs_head, 0);
        self.write(u32, .tx_descs_tail, 0);

        // zig fmt: off
        self.write(u32, .tctrl, 0
            | (1 << 1) // EN, transmit ENable
            | (1 << 3) // PSP, Pad Short Packages
            | (15 << 4) // CT, Collosition Threshold
            | (64 << 12) // COLD, COLlision Distance
            | (1 << 24) // RTLC, Re-Transmit on Late Collision
        );
        // zig fmt: on

        os.log("E1000: TX set up\n", .{});
    }

    fn init(self: *@This(), dev: os.platform.pci.Addr) !void {
        self.* = .{
            .base_addr = dev.barinfo(0).phy,
        };

        self.detectEeprom();
        self.readMAC();

        try self.setupRX();
        try self.setupTX();
    }

    pub fn format(
        self: *const @This(),
        fmt: anytype,
    ) !void {
        try writer.print(
            "Base MMIO address: 0x{X}, mac: {x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}, eeprom: {}",
            .{
                self.base_addr,
                self.mac[0],
                self.mac[1],
                self.mac[2],
                self.mac[3],
                self.mac[4],
                self.mac[5],
                self.advertises_eeprom,
            },
        );
    }
};

fn controllerTask(dev: os.platform.pci.Addr) void {
    var c: Controller = undefined;
    c.init(dev) catch |err| {
        os.log("E1000: Error while initializing: {}\n", .{err});
        if (@errorReturnTrace()) |trace| {
            os.kernel.debug.dumpStackTrace(trace);
        } else {
            os.log("No error trace.\n", .{});
        }
    };

    os.log("E1000: Inited controller: {}\n", .{c});
}

pub fn registerController(dev: os.platform.pci.Addr) void {
    if (comptime (!config.drivers.net.e1000.enable))
        return;

    dev.command().write(dev.command().read() | 0x6);
    os.vital(os.thread.scheduler.spawnTask(controllerTask, .{dev}), "Spawning e1000 controller task");
}
