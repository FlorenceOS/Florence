usingnamespace @import("root").preamble;
const kepler = os.kepler;

/// InterruptObject is a source of interrupts of some kind
/// InterruptObject will typically be embedded in the other
/// object that contains info about the interrupt vector like
/// gsi vector etc (depends on the interrupt source)
/// To create InterruptObject, two callback fields
/// unlink() and dispose() should be set.
/// NOTE: InterruptObject is strictly thread local
/// and assumes that raise() is called from the
/// thread owning queue.
/// NOTE: After unlink() was called, raise()
/// can no longer be called
pub const InterruptObject = struct {
    /// Unlink function pointer
    /// Called when owner of InterruptObject unsubscribes
    /// from further interrupt notifications. Called
    /// with interrupts disabled
    unlink: fn (*@This()) void,
    /// Dispose function pointer.
    /// Allows interrupt controller driver to free
    /// InterruptObject along with all other things
    dispose: fn (*@This()) void,

    /// Set to true if owner has unsubscribed from
    /// interrupt source
    dying: bool,
    /// Set to true if note was sent
    sent: bool,
    /// Note that is sent on InterruptRaised event
    note: kepler.ipc.Note,
    /// Target queue
    queue: *kepler.ipc.NoteQueue,

    /// Init method. Queue reference is borrowed
    pub fn init(self: *@This(), queue: *kepler.ipc.NoteQueue, unlink: fn (*@This()) void, dispose: fn (*@This()) void) void {
        self.dying = false;
        self.sent = false;
        self.queue = queue.borrow();
        self.unlink = unlink;
        self.dispose = dispose;
    }

    /// Raise method. Called from interrupt handler
    pub fn raise(self: *@This()) void {
        std.debug.assert(!self.dying);
        // If note is already sent, no need to resend
        if (@atomicLoad(bool, &self.sent, .Unordered)) {
            return;
        }
        // Fill out note fields
        self.note.typ = .InterruptRaised;
        self.note.owner_ref = .{ .interrupt = self };
        // Try sending note
        @atomicStore(bool, &self.sent, true, .Unordered);
        self.queue.send(&self.note) catch {
            // Queue could not be shut down, as object is not dying
            // and hence thread was not yet terminated => it's
            // queue has not been destroyed yet.
            @panic("Failed to sent note from interrupt handler");
        };
    }

    /// Drop owning reference. Calls unlink()
    pub fn shutdown(self: *@This()) void {
        const state = os.platform.get_and_disable_interrupts();
        self.dying = true;
        self.unlink(self);
        os.platform.set_interrupts(state);
        if (!@atomicLoad(bool, &self.sent, .Unordered)) {
            self.queue.drop();
            self.dispose(self);
        }
    }

    /// Drop non-owning reference (from note)
    pub fn drop(self: *@This()) void {
        if (self.dying) {
            self.queue.drop();
            self.dispose(self);
        } else {
            @atomicStore(bool, &self.sent, true, .Unordered);
        }
    }

    /// Returns true if object is still subscribed
    /// to interrupt notifications
    pub fn is_active(self: *@This()) bool {
        return !self.dying;
    }
};
