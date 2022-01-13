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
    hcs_params_1: u32,
    hcs_params_2: u32,
    hcs_params_3: u32,
    hcc_params_1: u32,
    db_regs_bar_offset: u32,
    run_regs_bar_offset: u32,
    gccparams2: u32,
};

const PortRegs = extern struct {
    portsc: u32,
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
    crcr: u64,
    _res_20: [0x30 - 0x20]u8,
    dcbaap: u64,
    config: u32,
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

const DBRegs = extern struct {
    db: [256]u32,
};

const Controller = extern struct {
    cap_regs: *volatile CapRegs,
    op_regs: *volatile OpRegs,
    run_regs: *volatile RunRegs,
    db_regs: *volatile DBRegs,
    context_size: usize = undefined,

    fn init(bar: usize) @This() {
        const cap_regs = os.platform.phys_ptr(*volatile CapRegs).from_int(bar).get_uncached();

        return .{
            .cap_regs = cap_regs,
            .op_regs = os.platform.phys_ptr(*volatile OpRegs).from_int(bar + cap_regs.capabilites_length).get_uncached(),
            .run_regs = os.platform.phys_ptr(*volatile RunRegs).from_int(bar + cap_regs.run_regs_bar_offset).get_uncached(),
            .db_regs = os.platform.phys_ptr(*volatile DBRegs).from_int(bar + cap_regs.db_regs_bar_offset).get_uncached(),
        };
    }

    fn extcapsPtr(self: @This()) [*]volatile u32 {
        const eoff = ((self.cap_regs.hcc_params_1 & 0xFFFF0000) >> 16) * 4;
        return @intToPtr([*]u32, @ptrToInt(self.cap_regs) + eoff);
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
        if(!self.halted()) self.halt();

        self.op_regs.usbcmd.reset.write(true);
    }

    fn ready(self: @This()) bool {
        return !self.op_regs.usbsts.controller_not_ready.read();
    }

    fn waitReady(self: @This()) void {
        while(!self.ready()) os.thread.scheduler.yield();
    }
};

fn controllerTask(dev: os.platform.pci.Addr) !void {
    const bar = dev.barinfo(0);
    var controller = Controller.init(bar.phy);
    controller.claim();

    const usb3 = dev.read(u32, 0xDC);
    log(.debug, "Switching usb3 ports: 0x{X}", .{usb3});
    dev.write(u32, 0xD8, usb3);

    const usb2 = dev.read(u32, 0xD4);
    log(.debug, "Switching usb2 ports: 0x{X}", .{usb2});
    dev.write(u32, 0xD0, usb2);

    controller.reset();
    log(.debug, "Controller reset.", .{});

    controller.waitReady();
    controller.start();

    controller.op_regs.config = 44;
    controller.context_size = if ((controller.cap_regs.hcc_params_1 & 0b10) != 0) 64 else 32;

    log(.debug, "context size: {d}", .{controller.context_size});
}

pub fn registerController(dev: os.platform.pci.Addr) void {
    if (comptime (!config.drivers.usb.xhci.enable))
        return;

    dev.command().write(dev.command().read() | 0x6);
    os.vital(os.thread.scheduler.spawnTask("XHCI controller task", controllerTask, .{dev}), "Spawning XHCI controller task");
}
