const os = @import("root").os;
const atmcqueue = os.lib.atmcqueue;

pub const Task = struct {
  registers: os.platform.InterruptFrame = undefined,
  allocated_core_id: usize = undefined,
  platform_data: os.platform.thread.TaskData = undefined,
  atmcqueue_hook: atmcqueue.Node = undefined,
  paging_context: *os.platform.paging.PagingContext = undefined,
  stack: usize = undefined,

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
