const os = @import("root").os;
const lib = @import("../lib.zig");

pub const Object = struct {
    next_sibling: ?*Object = null,
    first_child: ?*Object = null,
    parent: ?*Object = null,

    // Getting a request for a yank means all of your children have already accepted and confirmed the yank,
    // so don't worry about them. Make sure that you can exit cleanly by reaching out to the remote server,
    // flushing blocks to the disk or whatever else you have to do.
    request_yank_callback: fn(*Object) anyerror!void,

    // The time has come to commit to the yank you previously promised to fullfill. In theory all the blocks
    // should be flushed to disk by now, and you shouldn't have to worry about that, so there's no way to fail
    // at this point. There's no turning back now.
    commit_yank_callback: fn(*Object) void,

    // Nevermind. You promised you could fulfill the yank, but someone else wasn't prepared to do that just yet.
    // You can start caching disk contents in ram again, or whatever you want to do.
    abort_yank_callback: fn(*Object) void,

    // Whoops. You're dead. Deal with it. Your entire family (parents/siblings/children) may be too. Sucks to be you.
    // Please try to not take the entire system down with you. Leave it in a good state for us who are *still alive*
    instant_yank_callback: fn(*Object) void,

    // Show yourself. Both your own and the global logging lock is grabbed when this is called, so don't take too long.
    // Also, please be terse.
    print_callback: fn(*Object) void,

    // The lock needs to be grabbed before adding or iterating children
    obj_lock: os.thread.Mutex = .{},

    pub fn lock(self: *@This()) void {
        self.obj_lock.lock();
    }

    pub fn unlock(self: *@This()) void {
        self.obj_lock.unlock();
    }

    /// Nicely request an object to be destroyed together with all of its children, like selecting "eject"
    /// on a usb storage device
    /// A successful `requestYank` needs to be followed either by `commitYank` or `abortYank`
    /// If it fails, you're already done.
    pub fn requestYank(self: *@This()) anyerror!void {
        self.lock();
        defer self.unlock();

        var child = self.first_child;

        errdefer {
            var rollback_child = self.first_child;
            while(rollback_child != child) : (child = child.next_sibling) {
                child.abortYank();
            }
        }

        while(child) : (child = child.next_sibling) {
            try child.requestYank();
        }

        errdefer self.abort_yank_callback(self);
        try self.request_yank_callback(self);
    }

    /// Either this one or `abortYank` is called after a successful `requestYank`
    pub fn commitYank(self: *@This()) void {
        self.lock();
        defer self.unlock();

        var child = self.first_child;
        while(child) : (child = child.next_sibling) {
            child.commitYank();
        }

        self.commit_yank_callback(self);
    }

    /// Either this one or `commitYank` is called after a successful `requestYank`
    pub fn abortYank(self: *@This()) void {
        self.lock();
        defer self.unlock();

        self.abort_yank_callback(self);

        var child = self.first_child;
        while(child) : (child = child.next_sibling) {
            child.abortYank();
        }
    }

    /// `instantYank`ing stuff is for when something has been removed from the system and all of it needs
    /// to be destroyed to represent physical state (like a usb device being removed without warning)
    pub fn instantYank(self: *@This()) void {
        self.lock();
        defer self.unlock();

        var child = self.first_child;
        while(child) : (child = child.next_sibling) {
            child.instantYank();
        }

        self.instant_yank_callback(self);
    }

    /// Lock should be grabbed when calling this
    pub fn addChild(self: *@This(), new_child: *Object) void {
        new_child.next_sibling = self.first_child;
        self.first_child = new_child;
        new_child.parent = self;
    }

    /// Lock should be grabbed when calling this
    pub fn format(self: *@This(), fmt: anytype) void {
        _ = fmt;
        self.print_callback(self);
    }
};

pub fn init(comptime T: type, comptime obj_member_name: []const u8) Object {
    return .{
        .request_yank_callback = struct {
            fn f(o: *Object) anyerror!void {
                const t = @fieldParentPtr(T, obj_member_name, o);
                return @call(.{.modifier = .always_inline}, t.requestYank, .{});
            }
        }.f,

        .commit_yank_callback = struct {
            fn f(o: *Object) void {
                const t = @fieldParentPtr(T, obj_member_name, o);
                @call(.{.modifier = .always_inline}, t.commitYank, .{});
            }
        }.f,

        .abort_yank_callback = struct {
            fn f(o: *Object) void {
                const t = @fieldParentPtr(T, obj_member_name, o);
                @call(.{.modifier = .always_inline}, t.abortYank, .{});
            }
        }.f,

        .instant_yank_callback = struct {
            fn f(o: *Object) void {
                const t = @fieldParentPtr(T, obj_member_name, o);
                @call(.{.modifier = .always_inline}, t.instantYank, .{});
            }
        }.f,

        .print_callback = struct {
            fn f(o: *Object) void {
                const t = @fieldParentPtr(T, obj_member_name, o);
                @call(.{.modifier = .always_inline}, t.print, .{lib.output.fmt.doFmtNoEndl});
            }
        }.f,
    };
}
