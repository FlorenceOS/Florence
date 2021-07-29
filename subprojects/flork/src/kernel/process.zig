usingnamespace @import("root").preamble;

pub const address_space = @import("process/address_space.zig");
pub const memory_object = @import("process/memory_object.zig");

const kernel_linux_compat = config.kernel.linux_binary_compat;
const kernel_xnu_compat = config.kernel.xnu_binary_compat;

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

var lazy_zeroes = memory_object.lazyZeroes(os.memory.paging.rw());

pub const Process = struct {
    page_table: platform.paging.PagingContext,
    addr_space: address_space.AddrSpace,

    pub fn init(self: *@This()) !void {
        try os.thread.scheduler.spawnTask(initProcessTask, .{self});
    }

    fn initProcessTask(self: *@This()) !void {
        const task = os.platform.get_current_task();

        const userspace_base = 0x000400000;

        try self.addr_space.init(userspace_base, 0xFFFFFFF000);

        self.page_table = try os.platform.paging.PagingContext.make_userspace();
        task.paging_context = &self.page_table;
        errdefer task.paging_context.deinit();

        const entry = try copernicus.map(&self.addr_space);

        const stack_size = 0x2000;
        const stack_base = try self.addr_space.allocateAnywhere(stack_size);
        try self.addr_space.lazyMap(stack_base, stack_size, try lazy_zeroes.makeRegion());
        const stack_top = stack_base + stack_size;

        task.process = self;

        self.page_table.apply();
        os.platform.thread.enter_userspace(entry, 0, stack_top);
    }

    fn dequeue(frame: *platform.InterruptFrame) void {
        os.log("Dequeueing userspace task.\n", .{});
        os.thread.preemption.awaitForTaskAndYield(frame);
    }

    pub fn deinit() void {
        os.log("TODO: Process deinit\n", .{});
    }

    pub fn handleSyscall(self: *@This(), frame: *platform.InterruptFrame) void {
        resolveSyscall(frame)(self, frame);
    }

    pub fn onPageFault(self: *@This(), addr: usize, present: bool, fault_type: platform.PageFaultAccess, frame: *platform.InterruptFrame) void {
        self.addr_space.pageFault(addr, present, fault_type) catch |err| {
            const present_str: []const u8 = if (present) "present" else "non-present";
            os.log("Page fault in userspace process: {s} {} at 0x{X}\n", .{ present_str, fault_type, addr });
            os.log("Didn't handle the page fault: {}\n", .{err});
            if (@errorReturnTrace()) |trace| {
                os.kernel.debug.dumpStackTrace(trace);
            }
            frame.dump();
            frame.trace_stack();
            dequeue(frame);
        };
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
        os.log("Userspace process requested exit.\n", .{});
        dequeue(frame);
    }

    fn syscallUnknown(self: *@This(), frame: *platform.InterruptFrame) void {
        os.log("Process executed unknown syscall {}", .{syscallNumber(frame)});
        dequeue(frame);
    }
};
