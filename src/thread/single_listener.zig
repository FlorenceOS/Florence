const std = @import("std");

/// SingleListener is a helper that allows one thread
/// to listen for events triggered by many producers
pub const SingleListener = struct {
    /// Value that will be used for blocking
    const BLOCK_VAL: usize = @divFloor(std.math.maxInt(usize), 2);

    /// Index of last event that was aknowledged by the consumer
    last_ack: usize,
    /// Index of last event that was triggered
    last_triggered: usize,
    /// Last event captured after the queue was cancelled
    last_captured: usize,

    /// Get the number of not aknowledged events
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
    pub fn wait(self: *const @This()) void {
        while (self.diff() == 0) {
            // TODO: Rewrite with sleep support
        }
    }

    /// Aknowledge one event or wait for one
    pub fn ack(self: *@This()) void {
        self.wait();
        last_ack += 1;
    }

    /// Trigger one event
    pub fn trigger(self: *@This()) bool {
        const ticket =  @atomicRmw(usize, &self.last_triggered, .Add, 1, .AcqRel);
        return ticket < BLOCK_VAL;
    }

    /// Block new events
    pub fn block(self: *@This()) void {
        self.last_captured = @atomicRmw(usize, &self.last_triggered, .Xchg, BLOCK_VAL, .AcqRel);
    }

    /// Create SingleListener object
    pub fn init() @This() {
        return .{
            .last_ack = 0,
            .last_triggered = 0,
            .last_captured = 0,
        };
    }
};
