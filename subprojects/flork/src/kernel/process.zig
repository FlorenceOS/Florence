usingnamespace @import("root").preamble;

const log = @import("lib").output.log.scoped(.{
    .prefix = "kernel/process",
    .filter = .info,
}).write;

pub const address_space = @import("process/address_space.zig");
pub const memory_object = @import("process/memory_object.zig");

const platform = os.platform;
const copernicus = os.kernel.copernicus;

// Representation of a process in a kernel context
// We can have binary compatibility for an operating system (syscall numbers, process state)
// built into the kernel. If we do, this is where that is stored too.

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

    pub fn init(self: *@This(), name: []const u8) !void {
        try os.thread.scheduler.spawnTask("Userspace task", initProcessTask, .{ self, name });
    }

    fn initProcessTask(self: *@This(), name: []const u8) !void {
        const task = os.platform.get_current_task();

        task.secondary_name = name;

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

    fn exitProc(frame: *platform.InterruptFrame) void {
        // TODO: Stop all tasks and do whatever else is needed
        log(.info, "Exiting current userspace task.", .{});
        os.thread.scheduler.exitTask();
    }

    pub fn deinit() void {
        log(.warn, "TODO: Process deinit", .{});
    }

    pub fn handleSyscall(self: *@This(), frame: *platform.InterruptFrame) void {
        resolveSyscall(frame)(self, frame);
    }

    pub fn onPageFault(self: *@This(), addr: usize, present: bool, fault_type: platform.PageFaultAccess, frame: *platform.InterruptFrame) void {
        self.addr_space.pageFault(addr, present, fault_type) catch |err| {
            const present_str: []const u8 = if (present) "present" else "non-present";
            log(null, "Page fault in userspace process: {s} {e} at 0x{X}", .{ present_str, fault_type, addr });
            log(null, "Didn't handle the page fault: {e}", .{err});
            if (@errorReturnTrace()) |trace| {
                os.kernel.debug.dumpStackTrace(trace);
            }
            log(null, "Frame dump:\n{}", .{frame});
            frame.trace_stack();
            exitProc(frame);
        };
    }

    fn linuxWrite(self: *@This(), frame: *platform.InterruptFrame) void {
        const fd = syscallArg(frame, 0);
        switch (fd) {
            1, 2 => {
                const str_ptr = @intToPtr([*]const u8, syscallArg(frame, 1));
                const str_len = syscallArg(frame, 2);
                if (str_len > 0) {
                    const ends_with_endl = str_ptr[str_len - 1] == '\n';
                    const str: []const u8 = if (ends_with_endl) str_ptr[0 .. str_len - 1] else str_ptr[0..str_len];
                    log(null, "{s}: {s}", .{
                        os.platform.get_current_task().secondary_name.?,
                        str,
                    });
                }
            },
            else => {
                log(.warn, "linuxWrite to bad fd {d}", .{fd});
            },
        }
    }

    fn linuxExit(self: *@This(), frame: *platform.InterruptFrame) void {
        log(.info, "Userspace process requested exit.", .{});
        exitProc(frame);
    }

    fn syscallUnknown(self: *@This(), frame: *platform.InterruptFrame) void {
        log(.warn, "Process executed unknown syscall {d}", .{syscallNumber(frame)});
        exitProc(frame);
    }
};
