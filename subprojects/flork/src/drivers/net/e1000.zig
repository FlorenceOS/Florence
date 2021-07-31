usingnamespace @import("root").preamble;

fn controllerTask(dev: os.platform.pci.Addr) void {}

pub fn registerController(dev: os.platform.pci.Addr) void {
    if (comptime (!config.drivers.net.e1000.enable))
        return;

    dev.command().write(dev.command().read() | 0x6);
    os.vital(os.thread.scheduler.spawnTask(controllerTask, .{dev}), "Spawning e1000 controller task");
}
