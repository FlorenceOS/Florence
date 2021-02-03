const std = @import("std");
const os = @import("root").os;

const CoreID = os.platform.CoreID;

pub const CoreData = struct {
  current_task: ?*os.thread.Task,
  booted: bool,
  acpi_id: u64,
};

var bsp_data: [1]CoreData = [1]CoreData{undefined};

pub var cpus: []CoreData = bsp_data[0..];

pub fn prepare() void {
  os.platform.set_current_cpu(&cpus[0]);
}

pub fn init(num_cores: usize) !void {
  if(num_cores < 2)
    return;

  cpus = try os.memory.vmm.backed(.Eternal).alloc(CoreData, num_cores);
  cpus[0] = bsp_data[0];
  os.platform.set_current_cpu(&cpus[0]);
}
