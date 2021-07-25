usingnamespace @import("root").preamble;

pub const kernel_linux_compat = config.kernel.linux_binary_compat;
pub const kernel_xnu_compat = config.kernel.xnu_binary_compat;

// Representation of a process in a kernel context
// We can have binary compatibility for an operating system (syscall numbers, process state)
// built into the kernel. If we do, this is where that is stored too.

// We don't need windows binary compatibility as there is a kernel api dll
// which can just do florence sycalls'

fn resolveSyscall(frame: *platform.InterruptFrame) fn (*Process, *platform.InterruptFrame) platform.interruptReturn {
    switch (comptime platform.arch) {
        .x86_64 => {
            switch (frame.syscallNumber()) {
                //0 => return Process.linuxRead,
                1 => return Process.linuxWrite,
                //2 => return Process.linuxOpen,
                //3 => return Process.linuxClose,
                //257 => return Process.linuxOpenat,
                60 => return Process.linuxExit,
                else => {},
            }
        },
        .aarch64 => {
            switch (frame.syscallNumber()) {
                //56 => return Process.linuxOpenat,
                //57 => return Process.linuxClose,
                //63 => return Process.linuxRead,
                64 => return Process.linuxWrite,
                93 => return Process.linuxExit,
                else => {},
            }
        },
    }

    return Process.syscallUnknown;
}

pub const Process = struct {
    userspace_task: os.thread.Task,
    page_table: os.platform.paging.PagingContext,
    addr_space_alloc: os.memory.range_alloc.RangeAlloc,

    pub fn init(self: *@This()) !void {
        self.addr_space_alloc = .{};
        _ = try self.addr_space_alloc.addRange(.{
            .base = 0x000400000,
            .size = 0xFFF000000,
        });

        self.page_table = try os.platform.paging.PagingContext.make_userspace();
        self.userspace_task.paging_context = &self.page_table;

        errdefer self.userspace_task.paging_context.deinit();

        try os.thread.scheduler.spawnUserspaceTask(&self.userspace_task, 0x000400000, 0, 0x69696969);
    }

    pub fn deinit() void {
        self.userspace_task.paging_context.deinit();
    }

    pub fn enter() void {
        page_table.apply();
    }

    fn linuxRead(self: *@This(), frame: *platform.InterruptFrame) void {
        @panic("linuxRead");
    }

    fn linuxWrite(self: *@This(), frame: *platform.InterruptFrame) void {
        @panic("linuxWrite");
    }

    fn linuxOpen(self: *@This(), frame: *platform.InterruptFrame) void {
        @panic("linuxOpen");
    }

    fn linuxClose(self: *@This(), frame: *platform.InterruptFrame) void {
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
