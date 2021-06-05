const os = @import("root").os;
const lib = @import("root").lib;
const atomic_queue = lib.containers.atomic_queue;

const guard_size = os.platform.thread.stack_guard_size;
const map_size = os.platform.thread.task_stack_size;
const total_size = guard_size + map_size;
const nonbacked = os.memory.vmm.nonbacked();

/// Separate execution unit
pub const Task = struct {
    /// General task registers that are preserved on every interrupt
    registers: os.platform.InterruptFrame = undefined,

    /// Core ID task is allocated to
    allocated_core_id: usize = undefined,

    /// Platform-specific data related to the task (e.g. TSS on x86_64)
    platform_data: os.platform.thread.TaskData = undefined,

    /// Hook for the task queue
    atomic_queue_hook: atomic_queue.Node = undefined,

    /// Virtual memory space task runs in
    paging_context: *os.platform.paging.PagingContext = undefined,

    /// Top of the stack used by the task
    stack: usize = undefined,

    /// Allocate stack for the task. Used in scheduler make_task routine
    pub fn allocate_stack(self: *@This()) !void {
        // Allocate non-backing virtual memory
        const slice = (try nonbacked.allocFn(nonbacked, total_size, 1, 1, 0));
        errdefer _ = nonbacked.resizeFn(nonbacked, slice, 1, 0, 1, 0) catch @panic("task alloc stack");
        // Map pages
        const virt = @ptrToInt(slice.ptr);
        try os.memory.paging.map(.{
            .virt = virt + guard_size,
            .size = map_size,
            .perm = os.memory.paging.rw(),
            .memtype = .MemoryWriteBack,
        });
        self.stack = virt + total_size;
    }

    /// Free stack used by the task. Used in User Request Monitor on task termination
    pub fn free_stack(self: *@This()) void {
        const virt = self.stack - total_size;
        // Unmap stack pages
        os.memory.paging.unmap(.{ .virt = virt + guard_size, .size = map_size, .reclaim_pages = true });
        // Free nonbacked memory
        _ = nonbacked.resizeFn(nonbacked, @intToPtr([*]u8, virt)[0..total_size], 1, 0, 1, 0) catch @panic("task free stack");
    }
};
