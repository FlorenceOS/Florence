const os = @import("root").os;

const queue = @import("lib").containers.queue;

/// Semaphore waiting queue node
const WaitingNode = struct {
    /// Number of resources thread is waiting for
    count: usize = undefined,
    /// Task waiting to be waken up
    task: *os.thread.Task = undefined,
    /// Queue hook
    queue_hook: queue.Node = undefined,
};

/// Semaphore is lock that should be used for synchronizing operations that may take too long and/or
/// can't be run in interrupt disabled context (e.g. you need to use it if you allocate memory
/// in locked section). Unlike Mutex, it can be also used to grant access to more than one resource
pub const Semaphore = struct {
    /// Atomic queue of waiting tasks
    queue: queue.Queue(WaitingNode, "queue_hook") = .{},
    /// Spinlock used to prevent more than one thread from accessing mutex data
    spinlock: os.thread.Spinlock = .{},
    /// Number of resources available
    available: usize,

    /// Create semaphore with N resources available
    pub fn init(count: usize) @This() {
        return .{ .available = count };
    }

    /// Acquire `count` resources. Don't call from interrupt context!
    pub fn acquire(self: *@This(), count: usize) void {
        const lock_state = self.spinlock.lock();

        const task = os.platform.get_current_task();

        if (self.available >= count) {
            self.available -= count;
            self.spinlock.unlock(lock_state);
            return;
        }

        var waiting_token: WaitingNode = .{};
        waiting_token.count = count;
        waiting_token.task = task;

        self.queue.enqueue(&waiting_token);
        os.thread.scheduler.waitReleaseSpinlock(&self.spinlock);

        os.platform.set_interrupts(lock_state);
    }

    /// Release `count` resources, can be called from interrupt context but could be slow
    /// if hit _really_ often
    pub fn release(self: *@This(), count: usize) void {
        const lock_state = self.spinlock.lock();

        self.available += count;
        if (self.queue.front()) |next| {
            const resources_needed = next.count;
            if (self.available >= resources_needed) {
                self.available -= resources_needed;
                _ = self.queue.dequeue();
                os.thread.scheduler.wake(next.task);
            }
        }
        self.spinlock.unlock(lock_state);
    }
};
