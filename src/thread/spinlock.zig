const os = @import("root").os;

// A simple spinlock
// Can be used as an SMP synchronization primitive
pub const Spinlock = struct {
  taken: bool = false,

  // Try grabbing lock and disabling interrupts atomically
  pub fn try_lock(self: *@This()) ?os.platform.InterruptState {
    const state = os.platform.get_and_disable_interrupts();
    if(self.try_grab()) return state;
    os.platform.set_interrupts(state);
    return null;
  }

  // Grabs lock and disables interrupts atomically.
  pub fn lock(self: *@This()) os.platform.InterruptState {
    while(true) {
      const state = self.try_lock();

      if(state) |s| { return s; }

      os.platform.spin_hint();
    }
  }

  pub fn try_grab(self: *@This()) bool {
    return !@atomicRmw(bool, &self.taken, .Xchg, true, .AcqRel);
  }

  // Grab lock without disabling interrupts
  pub fn grab(self: *@This()) void {
    while(!self.try_grab()) {
      os.platform.spin_hint();
    }
  }

  // Release lock without restoring interrupt state
  pub fn ungrab(self: *@This()) void {
    @import("std").debug.assert(self.taken);
    @atomicStore(bool, &self.taken, false, .Release);
  }

  // Releases lock while atomically restoring interrupt state
  pub fn unlock(self: *@This(), s: os.platform.InterruptState) void {
    self.ungrab();
    os.platform.set_interrupts(s);
  }
};
