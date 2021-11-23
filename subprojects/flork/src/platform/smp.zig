usingnamespace @import("root").preamble;

const std = @import("std");
const config = @import("config");

const CoreID = os.platform.CoreID;

/// Maximum number of supported CPUs
const max_cpus = comptime config.kernel.max_cpus;

/// CPUs data
var core_datas: [max_cpus]CoreData = [1]CoreData{undefined} ** max_cpus;

/// Count of CPUs that have not finished booting.
/// Assigned in stivale2.zig
pub var cpus_left: usize = undefined;

/// Pointer to CPUS data
pub var cpus: []CoreData = core_datas[0..1];

pub const CoreData = struct {
    current_task: *os.thread.Task = undefined,
    booted: bool,
    panicked: bool,
    acpi_id: u64,
    executable_tasks: os.thread.ReadyQueue,
    tasks_count: usize,
    platform_data: os.platform.thread.CoreData,
    int_stack: usize,
    sched_stack: usize,

    pub fn id(self: *@This()) usize {
        return @import("lib").util.pointers.getIndex(self, cpus);
    }

    fn bootstrap_stack(size: usize) usize {
        const guard_size = os.platform.thread.stack_guard_size;
        const total_size = guard_size + size;
        // Allocate non-backing virtual memory
        const nonbacked = os.memory.vmm.nonbacked();
        const virt = @ptrToInt(os.vital(nonbacked.allocFn(nonbacked, total_size, 1, 1, 0), "bootstrap stack valloc").ptr);
        // Map pages
        os.vital(os.memory.paging.map(.{
            .virt = virt + guard_size,
            .size = size,
            .perm = os.memory.paging.rw(),
            .memtype = .MemoryWriteBack,
        }), "bootstrap stack map");
        return virt + total_size;
    }

    // Called from BSP to bootstrap stacks for AP
    pub fn bootstrap_stacks(self: *@This()) void {
        self.int_stack = CoreData.bootstrap_stack(os.platform.thread.int_stack_size);
        self.sched_stack = CoreData.bootstrap_stack(os.platform.thread.sched_stack_size);
    }

    // Called from AP when AP is ready to get tasks to run
    pub fn bootstrap_tasking(self: *@This()) noreturn {
        const bootstrap_handler = struct {
            // Wait for the first task and run it
            pub fn bootstrap(frame: *os.platform.InterruptFrame, _: usize) void {
                _ = @atomicRmw(usize, &os.platform.smp.cpus_left, .Sub, 1, .AcqRel);
                const cpu = os.platform.thread.get_current_cpu();
                const task = cpu.executable_tasks.dequeue();
                frame.* = task.registers;
                task.paging_context.apply();
                os.platform.set_current_task(task);
                task.platform_data.loadState();
            }
        }.bootstrap;
        // Call bootstrap callback on a scheduler stack
        os.platform.sched_call(bootstrap_handler, undefined);
        unreachable;
    }
};

pub fn prepare() void {
    os.platform.thread.set_current_cpu(&cpus[0]);
    cpus[0].panicked = false;
    cpus[0].tasks_count = 1;
    cpus[0].platform_data = .{};
}

pub fn init(num_cores: usize) void {
    if (num_cores < 2)
        return;

    cpus.len = std.math.min(num_cores, max_cpus);

    // for(cpus[1..]) |*c| {
    // AAAAAAAAAAAAAAAAAAAAA https://github.com/ziglang/zig/issues/7968
    // Nope, can't do that. Instead we have to do the following:
    var i: usize = 1;
    while (i < cpus.len) : (i += 1) {
        const c = &cpus[i];
        // ugh.

        c.panicked = false;
        c.tasks_count = 0;
        c.executable_tasks.init(c);
        c.bootstrap_stacks();
        c.platform_data = .{};
    }
}
