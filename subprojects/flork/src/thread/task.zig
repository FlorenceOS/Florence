const os = @import("root").os;

const std = @import("std");

const atomic_queue = @import("lib").containers.atomic_queue;

const guard_size = os.platform.thread.stack_guard_size;
const map_size = os.platform.thread.task_stack_size;
const total_size = guard_size + map_size;
const vmm = os.memory.vmm;

/// Separate execution unit
pub const Task = struct {
    /// General task registers that are preserved on every interrupt
    registers: os.platform.InterruptFrame = undefined,

    /// Core ID task is allocated to
    allocated_core_id: usize = undefined,

    /// Platform-specific data related to the task (e.g. TSS on x86_64)
    platform_data: os.platform.thread.TaskData = undefined,

    /// Hook for the task queue
    queue_hook: atomic_queue.Node = undefined,

    /// Virtual memory space task runs in
    paging_context: *os.platform.paging.PagingContext = undefined,

    /// Top of the stack used by the task
    stack: usize = undefined,

    /// The process context that the task currently is executing within
    process: ?*os.kernel.process.Process = null,

    /// The name assigned on task creation
    name: []const u8,

    /// The name set by the task itself, if any
    secondary_name: ?[]const u8 = null,

    /// Allocate stack for the task. Used in scheduler makeTask routine
    pub fn allocStack(self: *@This()) !void {
        // Allocate non-backing virtual memory
        const virt = try vmm.allocNonbacked(total_size, 1, 1);
        errdefer {
            vmm.freeNonbacked(virt, total_size) catch {
                @panic("allocStack errdefer fail");
            };
        }
        // Map pages
        try os.memory.paging.map(.{
            .virt = virt + guard_size,
            .size = map_size,
            .perm = os.memory.paging.rw(),
            .memtype = .MemoryWriteBack,
        });
        self.stack = virt + total_size;
    }

    /// Free stack used by the task. Used in User Request Monitor on task termination
    pub fn freeStack(self: *@This()) void {
        const virt = self.stack - total_size;
        // Unmap stack pages
        os.memory.paging.unmap(.{
            .virt = virt + guard_size,
            .size = map_size,
            .reclaim_pages = true,
        });
        // Free nonbacked memory
        vmm.freeNonbacked(virt, total_size) catch @panic("task free stack");
    }

    pub fn enqueue(self: *@This()) void {
        os.platform.smp.cpus[self.allocated_core_id].executable_tasks.enqueue(self);
    }
};
