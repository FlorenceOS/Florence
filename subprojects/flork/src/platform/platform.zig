usingnamespace @import("root").preamble;

// Submodules
pub const acpi = @import("acpi.zig");
pub const pci = @import("pci.zig");
pub const devicetree = @import("devicetree.zig");
pub const smp = @import("smp.zig");

// Anything else comes from this platform specific file
pub const arch = if (@hasField(std.builtin, "arch")) std.builtin.arch else std.Target.current.cpu.arch;
pub const endian = if (@hasField(std.builtin, "endian")) std.builtin.endian else arch.endian();
usingnamespace @import(switch (arch) {
    .aarch64 => "aarch64/aarch64.zig",
    .x86_64 => "x86_64/x86_64.zig",
    else => unreachable,
});

const assert = @import("std").debug.assert;

pub const PageFaultAccess = enum {
    Read,
    Write,
    InstructionFetch,
};

fn attempt_handle_physmem_page_fault(base: usize, addr: usize, map_type: os.platform.paging.MemoryType) bool {
    if (base <= addr and addr < base + os.memory.paging.kernel_context.max_phys) {
        // Map 1G of this memory
        const phys = addr - base;
        const phys_gb_aligned = lib.util.libalign.alignDown(usize, 1024 * 1024 * 1024, phys);

        os.vital(os.memory.paging.mapPhys(.{
            .virt = base + phys_gb_aligned,
            .phys = phys_gb_aligned,
            .size = 1024 * 1024 * 1024,
            .perm = os.memory.paging.rw(),
            .memtype = map_type,
        }), "Lazily mapping physmem");

        return true;
    }

    return false;
}

fn handle_physmem_page_fault(addr: usize) bool {
    const context = &os.memory.paging.kernel_context;
    if (attempt_handle_physmem_page_fault(context.wb_virt_base, addr, .MemoryWriteBack)) {
        return true;
    }
    if (attempt_handle_physmem_page_fault(context.wc_virt_base, addr, .DeviceWriteCombining)) {
        return true;
    }
    if (attempt_handle_physmem_page_fault(context.uc_virt_base, addr, .DeviceUncacheable)) {
        return true;
    }
    return false;
}

pub fn page_fault(addr: usize, present: bool, access: PageFaultAccess, frame: anytype) void {
    // We lazily map some physical memory, see if this is what's happening
    if (!present) {
        switch (access) {
            .Read, .Write => if (handle_physmem_page_fault(addr)) return,
            else => {},
        }
    }

    os.log("Platform: Unhandled page fault on {s} at 0x{x}, present: {}\n", .{
        @tagName(access),
        addr,
        present,
    });

    frame.dump();
    frame.trace_stack();
    @panic("Page fault");
}

pub fn hang() noreturn {
    _ = get_and_disable_interrupts();
    while (true) {
        await_interrupt();
    }
}

pub fn set_current_task(task_ptr: *os.thread.Task) void {
    thread.get_current_cpu().current_task = task_ptr;
}

pub fn get_current_task() *os.thread.Task {
    return thread.get_current_cpu().current_task;
}

pub const virt_slice = struct {
    ptr: usize,
    len: usize,
};

pub fn phys_ptr(comptime ptr_type: type) type {
    return struct {
        addr: usize,

        pub fn get_writeback(self: *const @This()) ptr_type {
            return @intToPtr(ptr_type, os.memory.pmm.phys_to_write_back_virt(self.addr));
        }

        pub fn get_write_combining(self: *const @This()) ptr_type {
            return @intToPtr(ptr_type, os.memory.pmm.phys_to_write_combining_virt(self.addr));
        }

        pub fn get_uncached(self: *const @This()) ptr_type {
            return @intToPtr(ptr_type, os.memory.pmm.phys_to_uncached_virt(self.addr));
        }

        pub fn from_int(a: usize) @This() {
            return .{
                .addr = a,
            };
        }

        pub fn format(self: *const @This(), fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print("phys 0x{X}", .{self.addr});
        }
    };
}

pub fn phys_slice(comptime T: type) type {
    return struct {
        ptr: phys_ptr([*]T),
        len: usize,

        pub fn init(addr: usize, len: usize) @This() {
            return .{
                .ptr = phys_ptr([*]T).from_int(addr),
                .len = len,
            };
        }

        pub fn to_slice_writeback(self: *const @This()) []T {
            return self.ptr.get_writeback()[0..self.len];
        }

        pub fn to_slice_write_combining(self: *const @This()) []T {
            return self.ptr.get_write_combining()[0..self.len];
        }

        pub fn to_slice_uncached(self: *const @This()) []T {
            return self.ptr.get_uncached()[0..self.len];
        }
    };
}

pub const PhysBytes = struct {
    ptr: usize,
    len: usize,
};

/// Helper for calling functions on scheduler stack
pub fn sched_call(fun: fn (*os.platform.InterruptFrame, usize) void, ctx: usize) void {
    const state = os.platform.get_and_disable_interrupts();
    os.platform.thread.sched_call_impl(@ptrToInt(fun), ctx);
    os.platform.set_interrupts(state);
}
