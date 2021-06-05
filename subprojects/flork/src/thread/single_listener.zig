usingnamespace @import("root").preamble;

/// SingleListener is a helper that allows one thread
/// to listen for events triggered by many producers
pub const SingleListener = struct {
    /// Value that will be used for blocking
    const BLOCK_VAL: usize = @divFloor(std.math.maxInt(usize), 2);

    /// Index of last event that was acknowledged by the consumer
    last_ack: usize = 0,
    /// Index of last event that was triggered
    last_triggered: usize = 0,
    /// Last event captured after the queue was cancelled
    last_captured: usize = 0,
    /// Pointer to the waiting task
    thread: *os.thread.Task = undefined,
    /// True if thread can be woken up
    wakeup_allowed: bool = false,

    /// Get the number of not acknowledged events
    pub fn diff(self: *const @This()) usize {
        const triggered = @atomicLoad(usize, &self.last_triggered, .Acquire);
        if (triggered >= BLOCK_VAL) {
            return self.last_captured - self.last_ack;
        }
        return triggered - self.last_ack;
    }

    /// Aknowledge one event if present
    pub fn try_ack(self: *@This()) bool {
        if (self.diff() > 0) {
            self.last_ack += 1;
            return true;
        }
        return false;
    }

    /// Wait for events without actually acknowledging them
    pub fn wait(self: *@This()) void {
        // If there are events already, we can return immediatelly
        // Poll a few times to avoid doing costly wait operations
        const poll_num = 1024;
        var i: usize = 0;
        while (i < poll_num) : (i += 1) {
            if (self.diff() != 0) {
                return;
            }
            os.platform.spin_hint();
        }
        // Get pointer to the current task
        const task = os.platform.get_current_task();
        self.thread = task;
        // Time to jump on scheduler stack.
        const handler = struct {
            fn handler(frame: *os.platform.InterruptFrame, ctx: usize) void {
                // Get point to the queue passed as context pointer
                const listener = @intToPtr(*SingleListener, ctx);
                // Save state of the current task
                os.thread.preemption.store_current_state(frame);
                //os.log("Current state preserved!\n", .{});
                // Enable wakeup. After this point, task can be enqueued any minute
                @atomicStore(bool, &listener.wakeup_allowed, true, .SeqCst);
                // Check if there are any events
                if (listener.diff() != 0) {
                    // If there are some events, we race with trigger()
                    // (in a safe way of course) by doing CAS on thread member
                    const result = @cmpxchgStrong(bool, &listener.wakeup_allowed, true, false, .AcqRel, .Acquire);
                    if (result == null) {
                        // We got to wake thread up. Simply return, since frame is in a well-defined
                        // state
                        return;
                    }
                }
                // If we are here, it is not worth waking up the thread or
                // someone else did it for us. Just sit waiting for the next task
                os.thread.preemption.await_task_and_yield(frame);
            }
        }.handler;
        os.platform.sched_call(handler, @ptrToInt(self));
    }

    /// Aknowledge one event or wait for one
    pub fn ack(self: *@This()) void {
        self.wait();
        last_ack += 1;
    }

    /// Trigger one event
    pub fn trigger(self: *@This()) bool {
        const ticket = @atomicRmw(usize, &self.last_triggered, .Add, 1, .AcqRel);
        if (self.diff() != 0) {
            // We don't care if last_triggered is greater than BLOCK_VAL
            // since at this point wakeup_allowed would be false anyway
            const result = @cmpxchgStrong(bool, &self.wakeup_allowed, true, false, .AcqRel, .Acquire);
            if (result == null) {
                os.thread.scheduler.wake(self.thread);
            }
        }
        return ticket < BLOCK_VAL;
    }

    /// Block new events
    pub fn block(self: *@This()) void {
        self.last_captured = @atomicRmw(usize, &self.last_triggered, .Xchg, BLOCK_VAL, .AcqRel);
    }

    /// Create SingleListener object
    pub fn init() @This() {
        return .{};
    }
};
