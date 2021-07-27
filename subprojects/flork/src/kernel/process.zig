usingnamespace @import("root").preamble;

pub const kernel_linux_compat = config.kernel.linux_binary_compat;
pub const kernel_xnu_compat = config.kernel.xnu_binary_compat;

const platform = os.platform;
const copernicus = os.kernel.copernicus;

// Representation of a process in a kernel context
// We can have binary compatibility for an operating system (syscall numbers, process state)
// built into the kernel. If we do, this is where that is stored too.

// We don't need windows binary compatibility as there is a kernel api dll
// which can just do florence sycalls

pub fn currentProcess() ?*Process {
    return os.platform.get_current_task().process;
}

fn resolveSyscall(frame: *platform.InterruptFrame) fn (*Process, *platform.InterruptFrame) void {
    switch (comptime platform.arch) {
        .x86_64 => {
            switch (syscallNumber(frame)) {
                1 => return Process.linuxWrite,
                60 => return Process.linuxExit,
                else => {},
            }
        },
        .aarch64 => {
            switch (syscallNumber(frame)) {
                64 => return Process.linuxWrite,
                93 => return Process.linuxExit,
                else => {},
            }
        },
        else => unreachable,
    }

    return Process.syscallUnknown;
}

fn syscallNumber(frame: *platform.InterruptFrame) usize {
    switch (comptime platform.arch) {
        .x86_64 => return frame.rax,
        .aarch64 => return frame.x8,
        else => @compileError("syscallNumber not implemented for arch"),
    }
}

fn syscallArg(frame: *platform.InterruptFrame, num: usize) usize {
    switch (comptime platform.arch) {
        .x86_64 => {
            return switch (num) {
                0 => frame.rdi,
                1 => frame.rsi,
                2 => frame.rdx,
                3 => frame.r10,
                4 => frame.r8,
                5 => frame.r9,
                else => unreachable,
            };
        },
        .aarch64 => {
            return switch (num) {
                0 => frame.x0,
                1 => frame.x1,
                2 => frame.x2,
                3 => frame.x3,
                4 => frame.x4,
                5 => frame.x5,
                6 => frame.x6,
                7 => frame.x7,
                else => unreachable,
            };
        },
        else => @compileError("syscallArg not implemented for arch"),
    }
}

pub const Process = struct {
    userspace_task: os.thread.Task,
    page_table: platform.paging.PagingContext,
    addr_space_alloc: os.memory.range_alloc.RangeAlloc,

    pub fn init(self: *@This()) !void {
        const userspace_base = 0x000400000;

        const copernicus_base = copernicus.getBaseAddr();
        const copernicus_blob = copernicus.getBlob();

        self.addr_space_alloc = .{};
        _ = try self.addr_space_alloc.addRange(.{
            .base = userspace_base,
            .size = copernicus_base - userspace_base,
        });

        self.page_table = try os.platform.paging.PagingContext.make_userspace();
        self.userspace_task.paging_context = &self.page_table;
        errdefer self.userspace_task.paging_context.deinit();

        // This should probably just use some COW mapping of copernicus in the future
        const copernicus_phys = try os.memory.pmm.allocPhys(copernicus_blob.len);
        std.mem.copy(u8, os.platform.phys_ptr([*]u8).from_int(copernicus_phys).get_writeback()[0..copernicus_blob.len], copernicus_blob);

        try os.memory.paging.mapPhys(.{
            .context = &self.page_table,
            .phys = copernicus_phys,
            .virt = copernicus_base,
            .size = copernicus_blob.len,
            .perm = os.memory.paging.user(os.memory.paging.rwx()),
            .memtype = .MemoryWriteBack,
        });

        const stack_size = 0x2000;

        const stack_phys = try os.memory.pmm.allocPhys(stack_size);
        std.mem.set(u8, os.platform.phys_ptr([*]u8).from_int(stack_phys).get_writeback()[0..stack_size], 0);

        const stack_base = copernicus_base + copernicus_blob.len + 0x2000;

        try os.memory.paging.mapPhys(.{
            .context = &self.page_table,
            .phys = stack_phys,
            .virt = stack_base,
            .size = stack_size,
            .perm = os.memory.paging.user(os.memory.paging.rw()),
            .memtype = .MemoryWriteBack,
        });

        self.userspace_task.process = self;

        try os.thread.scheduler.spawnUserspaceTask(&self.userspace_task, copernicus_base, 0, stack_base + stack_size - 32);
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
        frame.dump();
        frame.trace_stack();
        dequeue(frame);
    }

    fn linuxWrite(self: *@This(), frame: *platform.InterruptFrame) void {
        const fd = syscallArg(frame, 0);
        switch (fd) {
            1, 2 => {
                const str_ptr = @intToPtr([*]const u8, syscallArg(frame, 1));
                const str_len = syscallArg(frame, 2);
                const ends_with_endl = str_ptr[str_len - 1] == '\n';
                os.log("USERSPACE LOG: {s}{s}", .{ str_ptr[0..str_len], if (ends_with_endl) @as([]const u8, "") else "\n" });
            },
            else => {
                os.log("linuxWrite to bad fd {}\n", .{fd});
            },
        }
    }

    fn linuxExit(self: *@This(), frame: *platform.InterruptFrame) void {
        os.log("Userspace process exited.\n", .{});
        dequeue(frame);
    }

    fn syscallUnknown(self: *@This(), frame: *platform.InterruptFrame) void {
        os.log("Process executed unknown syscall {}", .{syscallNumber(frame)});
        dequeue(frame);
    }
};
