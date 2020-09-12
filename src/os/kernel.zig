usingnamespace @import("common.zig");

//pub const panic = @import("../panic.zig").breakpoint_panic;

// const vmm = @import("../vmm.zig");
// const assert = std.debug.assert;

// fn do_heap_alloc(allocator: *std.mem.Allocator, len: usize, ptr_align: u29, len_align: u29) error{OutOfMemory}![]u8 {
//   assert(ptr_align <= 0x08);
//   return vmm.alloc_size(u8, len) catch return error.OutOfMemory;
// }

// fn do_heap_resize(allocator: *std.mem.Allocator, old_mem: []u8, len: new_size, len_align: u29) error{OutOfMemory}!usize {
//   assert(new_size == 0);
//   return vmm.free_size(@ptrToInt(&old_mem[0], old_mem.size));
// }
