usingnamespace @import("root").preamble;

/// Semaphore waiting queue node
const WaitingNode = struct {
    /// Number of resources thread is waiting for
    count: usize = undefined,
    /// Task waiting to be waken up
    task: *os.thread.Task = undefined,
    /// Is semaphore dead?
    dead: bool = false,
    /// Queue hook
    queue_hook: lib.containers.queue.Node = undefined,
};

/// Semaphore is lock that should be used for synchronizing operations that may take too long and/or
/// can't be run in interrupt disabled context (e.g. you need to use it if you allocate memory
/// in locked section). Unlike Mutex, it can be also used to grant access to more than one resource
pub const Semaphore = struct {
    /// Atomic queue of waiting tasks
    queue: lib.containers.queue.Queue(WaitingNode, "queue_hook") = .{},
    /// Spinlock used to prevent more than one thread from accessing mutex data
    spinlock: os.thread.Spinlock = .{},
    /// Number of resources available
    available: usize,
    /// Is semaphore dead?
    dead: bool = false,

    /// Create semaphore with N resources available
    pub fn init(count: usize) @This() {
        return .{ .available = count };
    }

    /// Try to acquire `count` resources. Don't call from interrupt context!
    pub fn try_acquire(self: *@This(), count: usize) !void {
        const task = os.platform.get_current_task();

        const lock_state = self.spinlock.lock();
        if (self.dead) {
            self.spinlock.unlock(lock_state);
            return error.SemaphoreDead;
        }

        if (self.available >= count) {
            self.available -= count;
            self.spinlock.unlock(lock_state);
            return;
        }

        var waiting_token: WaitingNode = .{};
        waiting_token.count = count;
        waiting_token.task = task;

        self.queue.enqueue(&waiting_token);
        self.spinlock.ungrab();
        os.thread.scheduler.wait();

        if (waiting_token.dead) {
            return error.SemaphoreDead;
        }

        os.platform.set_interrupts(lock_state);
    }

    /// Release `count` resources
    pub fn release(self: *@This(), count: usize) void {
        const lock_state = self.spinlock.lock();
        if (self.dead) {
            self.spinlock.unlock(lock_state);
            return;
        }

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

    /// Kill semaphore
    pub fn kill(self: *@This()) void {
        const lock_state = self.spinlock.lock();
        self.dead = true;
        self.spinlock.unlock(lock_state);
        while (self.queue.dequeue()) |wait_node| {
            wait_node.dead = true;
            os.thread.scheduler.wake(wait_node.task);
        }
    }

    // Acquire `count` resources or panic. Don't call from interrupt context!
    pub fn acquire(self: *@This(), count: usize) void {
        self.try_acquire(count) catch { unreachable; };
    }
};
