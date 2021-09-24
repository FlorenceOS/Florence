usingnamespace @import("root").preamble;

const log = lib.output.log.scoped(.{
    .prefix = "NVMe",
    .filter = .info,
}).write;

fn controllerTask(addr: os.platform.pci.Addr) void {}

pub fn registerController(addr: os.platform.pci.Addr) void {
    if (comptime (!config.drivers.block.nvme.enable))
        return;

    addr.command().write(addr.command().read() | 0x6);

    os.thread.scheduler.spawnTask(controllerTask, .{addr}) catch |err| {
        log(.crit, "Failed to make controller task: {s}", .{@errorName(err)});
    };
}
