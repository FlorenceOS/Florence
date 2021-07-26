usingnamespace @import("root").preamble;

pub const kernel_linux_compat = config.kernel.linux_binary_compat;
pub const kernel_xnu_compat = config.kernel.xnu_binary_compat;

const platform = os.platform;

// Representation of a process in a kernel context
// We can have binary compatibility for an operating system (syscall numbers, process state)
// built into the kernel. If we do, this is where that is stored too.

// We don't need windows binary compatibility as there is a kernel api dll
// which can just do florence sycalls

pub fn currentProcess() *Process {
    return @fieldParentPtr(Process, "userspace_task", os.platform.get_current_task());
}

fn resolveSyscall(frame: *platform.InterruptFrame) fn (*Process, *platform.InterruptFrame) void {
    switch (comptime platform.arch) {
        .x86_64 => {
            switch (frame.syscallNumber()) {
                1 => return Process.linuxWrite,
                60 => return Process.linuxExit,
                else => {},
            }
        },
        .aarch64 => {
            switch (frame.syscallNumber()) {
                64 => return Process.linuxWrite,
                93 => return Process.linuxExit,
                else => {},
            }
        },
        else => unreachable,
    }

    return Process.syscallUnknown;
}

pub const Process = struct {
    userspace_task: os.thread.Task,
    page_table: platform.paging.PagingContext,
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

    fn dequeue(frame: *platform.InterruptFrame) void {
        os.log("Dequeueing userspace task.\n", .{});
        os.thread.preemption.awaitForTaskAndYield(frame);
    }

    pub fn deinit() void {
        self.userspace_task.paging_context.deinit();
    }

    pub fn handleSyscall(self: *@This(), frame: *platform.InterruptFrame) void {
        resolveSyscall(frame)(self, frame);
    }

    pub fn onPageFault(self: *@This(), addr: usize, present: bool, fault_type: platform.PageFaultAccess, frame: *platform.InterruptFrame) void {
        os.log("Page fault in userspace process: {} at 0x{X}\n", .{ fault_type, addr });
        dequeue(frame);
    }

    fn linuxWrite(self: *@This(), frame: *platform.InterruptFrame) void {
        @panic("linuxWrite");
    }

    fn linuxExit(self: *@This(), frame: *platform.InterruptFrame) void {
        os.log("Userspace process exited.\n", .{});
        dequeue(frame);
    }

    fn syscallUnknown(self: *@This(), frame: *platform.InterruptFrame) void {
        os.log("Process executed unknown syscall {}", .{frame.syscallNumber()});
        dequeue(frame);
    }
};
