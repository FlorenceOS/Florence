const os = @import("root").os;
const std = @import("std");
const lib = @import("lib");

const log = lib.output.log.scoped(.{
    .prefix = "kernel/platform",
    .filter = .info,
}).write;

// Submodules
pub const acpi = @import("acpi.zig");
pub const pci = @import("pci.zig");
pub const devicetree = @import("devicetree.zig");
pub const smp = @import("smp.zig");

// Anything else comes from this platform specific file
pub const arch = @import("builtin").target.cpu.arch;
pub const endian = arch.endian();
const platform = switch (arch) {
    .aarch64 => @import("aarch64/aarch64.zig"),
    .x86_64 => @import("x86_64/x86_64.zig"),
    else => unreachable,
};
usingnamespace platform;

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

    log(null, "Platform: Unhandled page fault on {e} at 0x{X}, present: {b}", .{
        access,
        addr,
        present,
    });

    log(null, "Frame dump:\n{}", .{frame});
    frame.trace_stack();
    @panic("Page fault");
}

pub fn hang() noreturn {
    _ = platform.get_and_disable_interrupts();
    while (true) {
        platform.await_interrupt();
    }
}

pub fn set_current_task(task_ptr: *os.thread.Task) void {
    platform.thread.get_current_cpu().current_task = task_ptr;
}

pub fn get_current_task() *os.thread.Task {
    return platform.thread.get_current_cpu().current_task;
}

pub const virt_slice = struct {
    ptr: usize,
    len: usize,
};

pub fn phys_ptr(comptime ptr_type: type) type {
    return struct {
        addr: usize,

        pub fn get_writeback(self: *const @This()) ptr_type {
            return @intToPtr(ptr_type, os.memory.paging.physToWriteBackVirt(self.addr));
        }

        pub fn get_write_combining(self: *const @This()) ptr_type {
            return @intToPtr(ptr_type, os.memory.paging.physToWriteCombiningVirt(self.addr));
        }

        pub fn get_uncached(self: *const @This()) ptr_type {
            return @intToPtr(ptr_type, os.memory.paging.physToUncachedVirt(self.addr));
        }

        pub fn from_int(a: usize) @This() {
            return .{
                .addr = a,
            };
        }

        pub fn cast(self: *const @This(), comptime to_type: type) phys_ptr(to_type) {
            return .{
                .addr = self.addr,
            };
        }

        pub fn format(self: *const @This(), fmt: anytype) void {
            fmt("phys 0x{X}", .{self.addr});
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
