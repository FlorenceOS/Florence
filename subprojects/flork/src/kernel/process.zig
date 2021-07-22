        @panic("linuxClose");
    }

    fn linuxOpenat(self: *@This(), frame: *platform.InterruptFrame) void {
        @panic("linuxOpen");
    }

    fn syscallUnknown(self: *@This(), frame: *platform.InterruptFrame) void {
        os.log("Process executed unknown syscall {}", .{frame.syscallNumber()});
        @panic("syscallUnknown");
    }
};

pub fn syscallEntry(frame: *platform.InterruptFrame) void {
    const userspace_task = os.thread.get_current_task();
    const proc = @fieldParentPtr(Process, "userspace_task", userspace_task);
    const handler = resolveSyscall();

    handler(proc, frame);
}
