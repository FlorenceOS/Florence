const os = @import("root").os;
const config = @import("config");
const std = @import("std");
const lib = @import("lib");

const bf = lib.util.bitfields;

const log = lib.output.log.scoped(.{
    .prefix = "usb/xhci",
    .filter = .info,
}).write;

const CapRegs = extern struct {
    capabilites_length: u8,
    _res_01: u8,
    version: u16,
    hcs_params_1: extern union {
        _raw: u32,

        max_slots: bf.Bitfield(u32, 0, 8),
        max_ports: bf.Bitfield(u32, 24, 8),
    },
    hcs_params_2: u32,
    hcs_params_3: u32,
    hcc_params_1: extern union {
        _raw: u32,

        capable_of_64bit: bf.Boolean(u32, 0),
        context_size_is_64bit: bf.Boolean(u32, 2),

        extended_caps_offset: bf.Bitfield(u32, 16, 16),
    },
    doorbell_regs_bar_offset: u32,
    run_regs_bar_offset: u32,
    gccparams2: u32,
};

const PortRegs = extern struct {
    portsc: extern union {
        _raw: u32,

        connected: bf.Boolean(u32, 0),
        enabled: bf.Boolean(u32, 1),

        over_current_active: bf.Boolean(u32, 3),
        port_reset: bf.Boolean(u32, 4),
    },
    portpmsc: u32,
    portli: u32,
    reserved: u32,
};

const OpRegs = extern struct {
    usbcmd: extern union {
        _raw: u32,

        run_not_stop: bf.Boolean(u32, 0),
        reset: bf.Boolean(u32, 1),
    },
    usbsts: extern union {
        _raw: u32,

        halted: bf.Boolean(u32, 0),
        controller_not_ready: bf.Boolean(u32, 11),
    },
    page_size: u32,
    _res_0C: [0x14 - 0x0C]u8,
    dnctrl: u32,
    crcr_low: extern union {
        _raw: u32,

        ring_cycle_state: bf.Boolean(u32, 0),
        command_stop: bf.Boolean(u32, 1),
        command_abort: bf.Boolean(u32, 2),
        command_ring_running: bf.Boolean(u32, 3),

        shifted_addr: bf.Bitfield(u32, 6, 32 - 6),
    },
    crcr_high: u32,
    _res_20: [0x30 - 0x20]u8,
    dcbaap_low: u32,
    dcbaap_high: u32,
    config: extern union {
        _raw: u32,

        max_slots_enabled: bf.Bitfield(u32, 0, 8),
    },
    _res_3C: [0x400 - 0x3C]u8,
    ports: [256]PortRegs,
};

const InterruptRegs = extern struct {
    iman: u32,
    imod: u32,
    erstsz: u32,
    res_0C: u32,
    erstba: u32,
    erdp: u32,
};

const RunRegs = extern struct {
    microframe_idx: u32,
    _res_04: [0x20 - 0x4]u8,
    interrupt_regs: [1024]InterruptRegs,
};

const SlotContext = extern struct {
    off_0x00: extern union {
        _raw: u32,

        route_string: bf.Bitfield(u32, 0, 20),
        speed: bf.Bitfield(u32, 20, 4),
        multi_tt: bf.Boolean(u32, 25),
        hub: bf.Boolean(u32, 26),
        context_entries: bf.Bitfield(u32, 27, 5),
    },
    off_0x04: extern union {
        _raw: u32,
    },
    off_0x08: extern union {
        _raw: u32,
    },
    off_0x0C: extern union {
        _raw: u32,
    },
    reserved_0x10: [0x10]u8,
};

const EndpointContext = extern struct {
    off_0x00: extern union {
        _raw: u32,
    },
    off_0x04: extern union {
        _raw: u32,
    },
    off_0x08: extern union {
        _raw: u32,
    },
    off_0x0C: extern union {
        _raw: u32,
    },
    off_0x10: extern union {
        _raw: u32,
    },
    reserved_0x14: [0x0C]u8,
};

comptime {
    std.debug.assert(@sizeOf(SlotContext) == 0x20);
    std.debug.assert(@sizeOf(SlotContext) == @sizeOf(EndpointContext));
}

const CommandTRB = extern struct {
    off_0x00: extern union {
        _raw: u32,
    },
    off_0x04: extern union {
        _raw: u32,
    },
    off_0x08: extern union {
        _raw: u32,
    },
    off_0x0C: extern union {
        _raw: u32,
    },
};

comptime {
    std.debug.assert(@sizeOf(CommandTRB) == 0x10);
}

const DeviceContext = extern struct {
    slot: SlotContext,
    endpoint_slots: [31]EndpointContext,

    fn endpoints(self: *const @This()) []EndpointContext {
        return self.endpoint_slots[0 .. self.slot.off_0x00.context_entries.read() - 1];
    }
};

const Controller = struct {
    cap_regs: *volatile CapRegs,
    op_regs: *volatile OpRegs,
    run_regs: *volatile RunRegs,
    doorbells: *volatile [256]u32,
    context_size: usize = undefined,
    slots: []DeviceContext = undefined,
    commands: []CommandTRB = undefined,

    fn init(bar: usize) @This() {
        const cap_regs = os.platform.phys_ptr(*volatile CapRegs).from_int(bar).get_uncached();

        var result = @This(){
            .cap_regs = cap_regs,
            .op_regs = os.platform.phys_ptr(*volatile OpRegs).from_int(bar + cap_regs.capabilites_length).get_uncached(),
            .run_regs = os.platform.phys_ptr(*volatile RunRegs).from_int(bar + cap_regs.run_regs_bar_offset).get_uncached(),
            .doorbells = os.platform.phys_ptr(*volatile [256]u32).from_int(bar + cap_regs.doorbell_regs_bar_offset).get_uncached(),
        };

        result.context_size = if (result.cap_regs.hcc_params_1.context_size_is_64bit.read()) 64 else 32;

        return result;
    }

    fn extcapsPtr(self: @This()) [*]volatile u32 {
        const off = self.cap_regs.hcc_params_1.extended_caps_offset.read();
        return @intToPtr([*]u32, @ptrToInt(self.cap_regs) + @as(usize, off) * 4);
    }

    fn claim(self: @This()) void {
        var ext = self.extcapsPtr();

        while (true) {
            const ident = ext[0];

            if (ident == ~@as(u32, 0))
                break;

            if ((ident & 0xFF) == 0)
                break;

            if ((ident & 0xFF) == 1) {
                // Bios semaphore
                const bios_sem = @intToPtr(*volatile u8, @ptrToInt(ext) + 2);
                const os_sem = @intToPtr(*volatile u8, @ptrToInt(ext) + 3);

                if (bios_sem.* != 0) {
                    log(.debug, "Controller is BIOS owned.", .{});
                    os_sem.* = 1;
                    while (bios_sem.* != 0) os.thread.scheduler.yield();
                    log(.debug, "Controller stolen from BIOS.", .{});
                }
            }

            const next_offset = (ident >> 8) & 0xFF;
            if (next_offset == 0) break;
            ext += next_offset;
        }
    }

    fn halted(self: @This()) bool {
        return self.op_regs.usbsts.halted.read();
    }

    fn halt(self: @This()) void {
        std.debug.assert(self.op_regs.usbcmd.run_not_stop.read());

        self.op_regs.usbcmd.run_not_stop.write(false);
        while (!self.halted()) os.thread.scheduler.yield();
    }

    fn start(self: @This()) void {
        std.debug.assert(self.halted());
        std.debug.assert(!self.op_regs.usbcmd.run_not_stop.read());

        self.op_regs.usbcmd.run_not_stop.write(true);
    }

    fn reset(self: @This()) void {
        if (!self.halted()) self.halt();

        self.op_regs.usbcmd.reset.write(true);
    }

    fn ready(self: @This()) bool {
        return !self.op_regs.usbsts.controller_not_ready.read();
    }

    fn waitReady(self: @This()) void {
        while (!self.ready()) os.thread.scheduler.yield();
    }

    fn ports(self: @This()) []volatile PortRegs {
        return self.op_regs.ports[0..self.cap_regs.hcs_params_1.max_ports.read()];
    }
};

fn controllerTask(dev: os.platform.pci.Addr, controller_c: Controller) !void {
    var controller = controller_c;
    controller.claim();

    const usb3 = dev.read(u32, 0xDC);
    log(.debug, "Switching usb3 ports: 0x{X}", .{usb3});
    dev.write(u32, 0xD8, usb3);

    const usb2 = dev.read(u32, 0xD4);
    log(.debug, "Switching usb2 ports: 0x{X}", .{usb2});
    dev.write(u32, 0xD0, usb2);

    controller.reset();
    log(.debug, "Controller reset", .{});

    controller.waitReady();
    log(.debug, "Controller ready", .{});

    // TODO: Enable interrupts here

    { // Device context allocation
        const slots = controller.cap_regs.hcs_params_1.max_slots.read();
        controller.op_regs.config.max_slots_enabled.write(slots);
        log(.debug, "Controller has {d} device context slots", .{slots});

        const context_bytes = @sizeOf(DeviceContext) * @as(usize, slots);
        const mem = try os.memory.pmm.allocPhys(context_bytes);

        controller.op_regs.dcbaap_low = @truncate(u32, mem);
        controller.op_regs.dcbaap_high = @intCast(u32, mem >> 32);

        controller.slots = os.platform.phys_ptr([*]DeviceContext).from_int(mem).get_uncached()[0..slots];
        for (controller.slots) |*slot| {
            slot.* = std.mem.zeroes(DeviceContext);
        }
    }

    { // Command ring allocation
        const commands = 16;
        const mem = try os.memory.pmm.allocPhys(@sizeOf(CommandTRB) * @as(usize, commands));

        controller.op_regs.crcr_low._raw = @truncate(u32, mem);
        controller.op_regs.crcr_high = @intCast(u32, mem >> 32);

        controller.commands = os.platform.phys_ptr([*]CommandTRB).from_int(mem).get_uncached()[0..commands];
        for (controller.commands) |*cmd| {
            cmd.* = std.mem.zeroes(CommandTRB);
        }
    }

    controller.start();
    log(.debug, "Controller started", .{});
}

pub fn registerController(dev: os.platform.pci.Addr) void {
    if (comptime (!config.drivers.usb.xhci.enable))
        return;

    var controller = Controller.init(dev.barinfo(0).phy);

    if (!controller.cap_regs.hcc_params_1.capable_of_64bit.read()) {
        log(.err, "Controller not 64 bit capable, ignoring", .{});
        return;
    }

    dev.command().write(dev.command().read() | 0x6);
    os.vital(os.thread.scheduler.spawnTask("XHCI controller task", controllerTask, .{ dev, controller }), "Spawning XHCI controller task");
}
