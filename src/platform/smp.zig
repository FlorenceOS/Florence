const std = @import("std");
const os = @import("root").os;

const CoreID = os.platform.CoreID;

const max_cpus = 512;

pub const CoreData = struct {
  current_task: ?*os.thread.Task,
  booted: bool,
  acpi_id: u64,
  executable_tasks: os.thread.ReadyQueue,

  pub fn id(self: *@This()) usize {
    return (@ptrToInt(self) - @ptrToInt(cpus.ptr))/@sizeOf(@This());
  }
};

var core_datas: [max_cpus]CoreData = [1]CoreData{undefined} ** max_cpus;

pub var cpus: []CoreData = core_datas[0..1];

pub fn prepare() void {
  os.platform.set_current_cpu(&cpus[0]);
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

    c.current_task = null;
    c.executable_tasks.init();
  }
}
