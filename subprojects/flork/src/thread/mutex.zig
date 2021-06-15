usingnamespace @import("root").preamble;

/// Mutex is lock that should be used for synchronizing operations that may take too long and/or
/// can't be run in interrupt disabled context (e.g. you need to use it if you allocate memory
/// in locked section)
pub const Mutex = struct {
    /// Thread that holds the mutex
    held_by: ?*os.thread.Task = null,
    /// Atomic queue of waiting tasks
    queue: os.thread.TaskQueue = .{},
    /// Spinlock used to prevent more than one thread from accessing mutex data
    spinlock: os.thread.Spinlock = .{},

    /// Wrapper for mutex std API
    const Held = struct {
        mtx: *Mutex,

        /// Release mutex
        pub fn release(self: *const @This()) void {
            self.mtx.unlock();
        }
    };

    /// Acquire method to be used by zig std
    pub fn acquire(self: *@This()) Held {
        self.lock();
        return .{ .mtx = self };
    }

    /// Lock mutex. Don't call from interrupt context!
    pub fn lock(self: *@This()) void {
        const lock_state = self.spinlock.lock();
        if (self.held_by == null) {
            self.held_by = os.platform.get_current_task();
            self.spinlock.unlock(lock_state);
            return;
        }
        self.queue.enqueue(os.platform.get_current_task());
        self.spinlock.ungrab();
        os.thread.scheduler.wait();
        os.platform.set_interrupts(lock_state);
    }

    /// Unlock mutex.
    pub fn unlock(self: *@This()) void {
        const lock_state = self.spinlock.lock();
        std.debug.assert(self.heldByMe());
        if (self.queue.dequeue()) |task| {
            @atomicStore(?*os.thread.Task, &self.held_by, task, .Release);
            os.thread.scheduler.wake(task);
        } else {
            @atomicStore(?*os.thread.Task, &self.held_by, null, .Release);
        }
        self.spinlock.unlock(lock_state);
    }

    /// Check if mutex is held by current task
    pub fn heldByMe(self: *const @This()) bool {
        const current_task = os.platform.get_current_task();
        return @atomicLoad(?*os.thread.Task, &self.held_by, .Acquire) == current_task;
    }
};
