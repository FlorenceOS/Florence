const os = @import("root").os;
const atmcqueue = os.lib.atmcqueue;

/// Separate execution unit
pub const Task = struct {
  /// General task registers that are preserved on every interrupt
  registers: os.platform.InterruptFrame = undefined,
  /// Core ID task is allocated to
  allocated_core_id: usize = undefined,
  /// Platform-specific data related to the task (e.g. TSS on x86_64)
  platform_data: os.platform.thread.TaskData = undefined,
  /// Hook for the task queue
  atmcqueue_hook: atmcqueue.Node = undefined,
  /// Virtual memory space task runs in
  paging_context: *os.platform.paging.PagingContext = undefined,
  /// Top of the stack used by the task
  stack: usize = undefined,

  /// Allocate stack for the task. Used in scheduler make_task routine
  pub fn allocate_stack(self: *@This()) !void {
    const guard_size = os.platform.thread.stack_guard_size;
    const map_size = os.platform.thread.task_stack_size;
    const total_size = guard_size + map_size;
    // Allocate non-backing virtual memory
    const nonbacked = os.memory.vmm.nonbacked();
    const slice = (try nonbacked.allocFn(nonbacked, total_size, 1, 1, 0));
    errdefer _ = nonbacked.resizeFn(nonbacked, slice, 1, 0, 1, 0) catch @panic("task alloc stack");
    // Map pages
    const virt = @ptrToInt(slice.ptr);
    try os.memory.paging.map(.{
      .virt = virt + guard_size,
      .size = map_size,
      .perm = os.memory.paging.rw(),
      .memtype = os.platform.paging.MemoryType.MemoryWritethrough
    });
    self.stack = virt + total_size;
  }

  /// Free stack used by the task. Used in User Request Monitor on task termination
  pub fn free_stack(self: *@This()) void {
    const guard_size = os.platform.thread.stack_guard_size;
    const total_size = guard_size + os.platform.thread.task_stack_size;
    const virt = self.stack - total_size;
    const mapped = virt + guard_size;
    const mapping_size = self.stack;
    const nonbacked = os.memory.vmm.nonbacked();
    // Unmap stack pages
    paging.unmap(.{ .virt = addr, .size = object.virtual_size(), .reclaim_pages = false });
    // Free nonbacked memory
    _ = nonbacked.resizeFn(nonbacked, @intToPtr([*]u8, virt)[0..total_size], 1, 0, 1, 0) catch @panic("task free stack");
  }
};
