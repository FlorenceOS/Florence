usingnamespace @import("root").preamble;

/// A simple spinlock
/// Can be used as an SMP synchronization primitive
pub const Spinlock = struct {
    serving: usize = 0,
    allocated: usize = 0,

    /// Grabs lock and disables interrupts atomically.
    pub fn lock(self: *@This()) os.platform.InterruptState {
        const ticket = @atomicRmw(usize, &self.allocated, .Add, 1, .AcqRel);
        while (true) {
            const state = os.platform.get_and_disable_interrupts();
            if (@atomicLoad(usize, &self.serving, .Acquire) == ticket) {
                return state;
            }
            os.platform.set_interrupts(state);
            os.platform.spin_hint();
        }
    }

    /// Grab lock without disabling interrupts
    pub fn grab(self: *@This()) void {
        const ticket = @atomicRmw(usize, &self.allocated, .Add, 1, .AcqRel);
        while (true) {
            if (@atomicLoad(usize, &self.serving, .Acquire) == ticket) {
                return;
            }
            os.platform.spin_hint();
        }
    }

    /// Release lock without restoring interrupt state
    pub fn ungrab(self: *@This()) void {
        _ = @atomicRmw(usize, &self.serving, .Add, 1, .AcqRel);
    }

    /// Releases lock while atomically restoring interrupt state
    pub fn unlock(self: *@This(), s: os.platform.InterruptState) void {
        self.ungrab();
        os.platform.set_interrupts(s);
    }
};
