usingnamespace @import("root").preamble;

/// Mutex is lock that should be used for synchronizing operations that may take too long and/or
/// can't be run in interrupt disabled context (e.g. you need to use it if you allocate memory
/// in locked section)
pub const Mutex = struct {
    /// Semaphore used for locking
    sema: os.thread.Semaphore = os.thread.Semaphore.init(1),

    /// Wrapper for mutex std API
    pub const Held = struct {
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
        self.sema.acquire(1);
    }

    /// Unlock mutex.
    pub fn unlock(self: *@This()) void {
        self.sema.release(1);
    }
};
