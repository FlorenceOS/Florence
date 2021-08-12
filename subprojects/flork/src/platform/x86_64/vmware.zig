usingnamespace @import("root").preamble;

const ps2 = @import("ps2.zig");
const ports = @import("ports.zig");
const eoi = @import("apic.zig").eoi;

fn do_op(self: *Command, comptime str: []const u8) void {
    var magic = VMWARE_MAGIC;
    var command = self.command;
    var port = self.port;
    var size = self.size;
    var source = self.source;
    var destination = self.destination;

    // zig fmt: off
    asm volatile (str
        : [_] "={eax}" (magic)
        , [_] "={rbx}" (size)
        , [_] "={cx}" (command)
        , [_] "={dx}" (port)
        , [_] "={rsi}" (source)
        , [_] "={rdi}" (destination)
        : [_] "{eax}" (magic)
        , [_] "{rbx}" (size)
        , [_] "{cx}" (command)
        , [_] "{dx}" (port)
        , [_] "{rsi}" (source)
        , [_] "{rdi}" (destination)
    );
    // zig fmt: on

    self.magic = magic;
    self.command = command;
    self.port = port;
    self.size = size;
    self.source = source;
    self.destination = destination;
}

const Command = struct {
    magic: u32 = undefined,
    command: u16 = undefined,
    port: u16 = undefined,
    size: usize = undefined,
    source: usize = undefined,
    destination: usize = undefined,

    fn send(self: *@This()) void {
        self.port = VMWARE_PORT;
        do_op(self,
            \\inl %%dx, %%eax
            \\
        );
    }

    fn send_hb(self: *@This()) void {
        self.port = VMWARE_PORTHB;
        do_op(self,
            \\rep outsb
            \\
        );
    }

    fn get_hb(self: *@This()) void {
        self.port = VMWARE_PORTHB;
        do_op(self,
            \\rep insb
            \\
        );
    }
};

const VMWARE_MAGIC: u32 = 0x564D5868;
const VMWARE_PORT: u16 = 0x5658;
const VMWARE_PORTHB: u16 = 0x5659;

const CMD_GETVERSION: u16 = 10;

const CMD_ABSPOINTER_DATA: u16 = 39;
const CMD_ABSPOINTER_STATUS: u16 = 40;
const CMD_ABSPOINTER_COMMAND: u16 = 41;

const ABSPOINTER_ENABLE: u32 = 0x45414552;
const ABSPOINTER_RELATIVE: u32 = 0xF5;
const ABSPOINTER_ABSOLUTE: u32 = 0x53424152;

fn detect() bool {
    var cmd = Command{
        .command = CMD_GETVERSION,
    };
    cmd.send();
    if (cmd.size != VMWARE_MAGIC) return false;
    if (cmd.magic == 0xFFFFFFFF) return false;
    return true;
}

var counter: usize = 0;

fn abscurorInterruptHandler(frame: *os.platform.InterruptFrame) void {
    // Drop byte from ps2 buffer
    counter += 1;

    _ = ports.inb(0x60);

    if (counter == 3) {
        counter = 0;

        var cmd = Command{
            .command = CMD_ABSPOINTER_STATUS,
            .size = 0,
        };

        cmd.send();

        const status = cmd.magic;

        if (status == 0xFFFF0000) {
            unreachable; // Mouse problem
        }

        const num_packets = @divTrunc(@truncate(u16, status), 4);

        var i: u16 = 0;
        while(i < num_packets) : (i += 1) {
            cmd.command = CMD_ABSPOINTER_DATA;
            cmd.size = 4;
            cmd.send();

            os.log("VMWARE: Mouse data: {}\n", .{cmd});
        }
    }

    eoi();
}

pub fn init() void {
    if (comptime (!config.kernel.x86_64.vmware.enable))
        return;

    if (!detect()) {
        os.log("VMWARE: Not detected\n", .{});
        return;
    }
    os.log("VMWARE: Detected\n", .{});

    var cmd = Command{};

    if (comptime config.kernel.x86_64.vmware.abscursor) {
        if (comptime (!config.kernel.x86_64.ps2.mouse.enable))
            @compileError("PS/2 mouse has to be enabled for vmware cursor support");

        os.log("VMWARE: Enabling abscursor...\n", .{});
        const state = os.platform.get_and_disable_interrupts();
        defer os.platform.set_interrupts(state);

        cmd.size = ABSPOINTER_ENABLE;
        cmd.command = CMD_ABSPOINTER_COMMAND;
        cmd.send();

        cmd.size = 0;
        cmd.command = CMD_ABSPOINTER_STATUS;
        cmd.send();

        cmd.size = 1;
        cmd.command = CMD_ABSPOINTER_DATA;
        cmd.send();

        cmd.size = ABSPOINTER_ABSOLUTE;
        cmd.command = CMD_ABSPOINTER_COMMAND;
        cmd.send();

        @import("interrupts.zig").add_handler(ps2.mouse_interrupt_vector, abscurorInterruptHandler, true, 0, 1);
    }
}
