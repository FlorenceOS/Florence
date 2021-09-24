usingnamespace @import("root").preamble;

const log = lib.output.log.scoped(.{
    .prefix = "VMWARE",
    .filter = .info,
}).write;

const ps2 = @import("ps2.zig");
const ports = @import("ports.zig");
const eoi = @import("apic.zig").eoi;

fn do_op(self: *const Command, port: u16, comptime str: []const u8) CommandResult {
    var rax: u64 = undefined;
    var rbx: u64 = undefined;
    var rcx: u64 = undefined;
    var rdx: u64 = undefined;
    var rsi: u64 = undefined;
    var rdi: u64 = undefined;

    // zig fmt: off
    asm volatile (str
        : [_] "={rax}" (rax)
        , [_] "={rbx}" (rbx)
        , [_] "={rcx}" (rcx)
        , [_] "={rdx}" (rdx)
        , [_] "={rsi}" (rsi)
        , [_] "={rdi}" (rdi)
        // https://github.com/ziglang/zig/issues/8107
        : [_] "{rax}" (@as(u64, VMWARE_MAGIC))
        , [_] "{rbx}" (@as(u64, self.size))
        , [_] "{rcx}" (@as(u64, self.command))
        , [_] "{rdx}" (@as(u64, port))
        , [_] "{rsi}" (@as(u64, self.source))
        , [_] "{rdi}" (@as(u64, self.destination))
    );
    // zig fmt: on

    return .{
        .rax = rax,
        .rbx = rbx,
        .rcx = rcx,
        .rdx = rdx,
        .rsi = rsi,
        .rdi = rdi,
    };
}

fn send(cmd: Command) CommandResult {
    return do_op(&cmd, VMWARE_PORT,
        \\inl %%dx, %%eax
        \\
    );
}

fn send_hb(cmd: Command) CommandResult {
    return do_op(&cmd, VMWARE_PORTHB,
        \\rep outsb
        \\
    );
}

fn get_hb(cmd: Command) CommandResult {
    return do_op(&cmd, VMWARE_PORTHB,
        \\rep insb
        \\
    );
}

const Command = struct {
    command: u16 = undefined,
    size: usize = undefined,
    source: usize = undefined,
    destination: usize = undefined,
};

const CommandResult = struct {
    rax: u64,
    rbx: u64,
    rcx: u64,
    rdx: u64,
    rsi: u64,
    rdi: u64,
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
    const reply = send(.{
        .command = CMD_GETVERSION,
    });
    if (@truncate(u32, reply.rbx) != VMWARE_MAGIC) return false;
    if (@truncate(u32, reply.rax) == 0xFFFFFFFF) return false;
    return true;
}

var counter: usize = 0;

fn abscurorInterruptHandler(frame: *os.platform.InterruptFrame) void {
    // Drop byte from ps2 buffer
    counter += 1;

    _ = ports.inb(0x60);

    if (counter == 3) {
        counter = 0;

        const status = send(.{
            .command = CMD_ABSPOINTER_STATUS,
            .size = 0,
        });

        if (@truncate(u32, status.rax) == 0xFFFF0000) {
            unreachable; // Mouse problem
        }

        const num_packets = @divTrunc(@truncate(u16, status.rax), 4);

        var i: u16 = 0;
        while (i < num_packets) : (i += 1) {
            const mouse_pkt = send(.{
                .command = CMD_ABSPOINTER_DATA,
                .size = 4,
            });

            const buttons = @truncate(u16, mouse_pkt.rax);
            const rmb = (buttons & 0x10) != 0;
            const lmb = (buttons & 0x20) != 0;
            const mmb = (buttons & 0x08) != 0;

            const scaled_x = @truncate(u16, mouse_pkt.rbx);
            const scaled_y = @truncate(u16, mouse_pkt.rcx);

            const scroll = @bitCast(i2, @truncate(u2, mouse_pkt.rdx));
        }
    }

    eoi();
}

pub fn init() void {
    if (comptime (!config.kernel.x86_64.vmware.enable))
        return;

    if (!detect()) {
        log(.info, "Not detected", .{});
        return;
    }
    log(.info, "Detected", .{});

    var cmd = Command{};

    if (comptime config.kernel.x86_64.vmware.abscursor) {
        if (comptime (!config.kernel.x86_64.ps2.mouse.enable))
            @compileError("PS/2 mouse has to be enabled for vmware cursor support");

        log(.info, "Enabling abscursor...", .{});
        const state = os.platform.get_and_disable_interrupts();
        defer os.platform.set_interrupts(state);

        _ = send(.{
            .command = CMD_ABSPOINTER_COMMAND,
            .size = ABSPOINTER_ENABLE,
        });

        _ = send(.{
            .command = CMD_ABSPOINTER_STATUS,
            .size = 0,
        });

        _ = send(.{
            .command = CMD_ABSPOINTER_DATA,
            .size = 1,
        });

        _ = send(.{
            .command = CMD_ABSPOINTER_COMMAND,
            .size = ABSPOINTER_ABSOLUTE,
        });

        @import("interrupts.zig").add_handler(ps2.mouse_interrupt_vector, abscurorInterruptHandler, true, 0, 1);
    }
}
