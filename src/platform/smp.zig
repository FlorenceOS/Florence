const std = @import("std");
const os = @import("root").os;

const CoreID = os.platform.CoreID;

/// Maximum number of supported CPUs
const max_cpus = 512;

/// Count of CPUs that have not finished booting.
/// Assigned in stivale2.zig
pub var cpus_left: usize = undefined;

/// Interrupt stack size
const int_stack_size = 65536;

pub const CoreData = struct {
  current_task: *os.thread.Task = undefined,
  booted: bool,
  panicked: bool,
  acpi_id: u64,
  executable_tasks: os.thread.ReadyQueue,
  tasks_count: usize,
  platform_data: os.platform.thread.CoreData,
  int_stack: usize,

  pub fn id(self: *@This()) usize {
    return os.lib.get_index(self, cpus);
  }

  pub fn bootstrap_int_stack(self: *@This()) void {
    const guard_size = int_stack_size;
    const total_size = guard_size + int_stack_size;
    // Allocate non-backing virtual memory
    const nonbacked = os.memory.vmm.nonbacked();
    const virt = @ptrToInt(os.vital(nonbacked.allocFn(nonbacked, total_size, 1, 1, 0), "bootstrap stack valloc").ptr);
    // Map pages
    os.vital(os.memory.paging.map(.{
      .virt = virt + guard_size,
      .size = int_stack_size,
      .perm = os.memory.paging.rw(),
      .memtype = os.platform.paging.MemoryType.MemoryWritethrough
    }), "bootstrap stack map");
    self.int_stack = virt + total_size;
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
    c.tasks_count = 0;
    c.executable_tasks.init();
    c.bootstrap_int_stack();
    c.platform_data = .{};
  }
}
