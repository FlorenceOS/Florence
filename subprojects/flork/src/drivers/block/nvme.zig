usingnamespace @import("root").preamble;

fn controllerTask(addr: os.platform.pci.Addr) void {}

pub fn registerController(addr: os.platform.pci.Addr) void {
    if (comptime (!config.drivers.block.nvme.enable))
        return;

    addr.command().write(addr.command().read() | 0x6);

    os.thread.scheduler.spawnTask(controllerTask, .{addr}) catch |err| {
        os.log("NVMe: Failed to make controller task: {s}\n", .{@errorName(err)});
    };
}
