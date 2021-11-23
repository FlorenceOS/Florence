usingnamespace @import("root").preamble;

const config = @import("config");

const log = @import("lib").output.log.scoped(.{
    .filter = .info,
    .prefix = "block/nvme",
}).write;

fn controllerTask(addr: os.platform.pci.Addr) void {}

pub fn registerController(addr: os.platform.pci.Addr) void {
    if (comptime (!config.drivers.block.nvme.enable))
        return;

    addr.command().write(addr.command().read() | 0x6);

    os.thread.scheduler.spawnTask("NVMe controller task", controllerTask, .{addr}) catch |err| {
        log(.crit, "Failed to make controller task: {s}", .{@errorName(err)});
    };
}
