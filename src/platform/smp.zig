const std = @import("std");
const os = @import("root").os;

const CoreID = os.platform.CoreID;

const max_cpus = 512;

pub const CoreData = struct {
  current_task: ?*os.thread.Task,
  booted: bool,
  panicked: bool,
  acpi_id: u64,
  executable_tasks: os.thread.ReadyQueue,
  tasks_count: usize,
  platform_data: os.platform.thread.CoreData,

  pub fn id(self: *@This()) usize {
    return os.lib.get_index(self, cpus);
  }
};

var core_datas: [max_cpus]CoreData = [1]CoreData{undefined} ** max_cpus;

pub var cpus: []CoreData = core_datas[0..1];

pub fn prepare() void {
  os.platform.thread.set_current_cpu(&cpus[0]);
  cpus[0].panicked = false;
  cpus[0].tasks_count = 1;
  cpus[0].platform_data = .{};
}

pub fn init(num_cores: usize) void {
  if(num_cores < 2)
    return;

  cpus.len = std.math.min(num_cores, max_cpus);

  // for(cpus[1..]) |*c| {
  // AAAAAAAAAAAAAAAAAAAAA https://github.com/ziglang/zig/issues/7968
  // Nope, can't do that. Instead we have to do the following:
  var i: usize = 1;
  while(i < cpus.len) : (i += 1) {
    const c = &cpus[i];
  // ugh.

    c.panicked = false;
    c.current_task = null;
    c.tasks_count = 0;
    c.executable_tasks.init();
    c.platform_data = .{};
  }
}
