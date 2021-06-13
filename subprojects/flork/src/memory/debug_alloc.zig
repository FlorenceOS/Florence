usingnamespace @import("root").preamble;

pub const DebugAlloc = struct {
    allocator: std.mem.Allocator = .{
        .allocFn = alloc,
        .resizeFn = resize,
    },

    backed: bool,

    fn alloc(allocator: *std.mem.Allocator, len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) std.mem.Allocator.Error![]u8 {
        const self = @fieldParentPtr(@This(), "allocator", allocator);
        const effective_len = lib.util.libalign.alignUp(usize, 0x1000, len);
        const bytes = try os.memory.vmm.sbrkNonbacked(0x2000 + effective_len);

        if (self.backed)
            os.memory.paging.map(.{
                .virt = @ptrToInt(bytes.ptr) + 0x1000,
                .size = effective_len,
                .perm = os.memory.paging.rw(),
                .memtype = .MemoryWriteBack,
            }) catch |err| {
                os.log("Got error {s} while mapping in DebugAlloc!\n", .{@errorName(err)});
                @panic("DebugAlloc map fail");
            };

        return bytes.ptr[0x1000 .. 0x1000 + len];
    }

    fn resize(allocator: *std.mem.Allocator, old_mem: []u8, old_align: u29, new_size: usize, len_align: u29, ret_addr: usize) std.mem.Allocator.Error!usize {
        const self = @fieldParentPtr(@This(), "allocator", allocator);
        if (new_size != 0) {
            os.log("Todo: DebugAlloc.resize(): actually resize\n", .{});
            @panic("");
        }

        if (self.backed)
            os.memory.paging.unmap(.{
                .virt = @ptrToInt(old_mem.ptr) + 0x1000,
                .size = old_mem.len,
                .reclaim_pages = true,
            });

        // Throw memory away, we don't wanna touch it again.

        return 0;
    }
};
