pub const Tss = packed struct {
    _1: u32 = 0,
    rsp: [3]u64 = [1]u64{0} ** 3,
    _2: u64 = 0,
    ist: [7]u64 = [1]u64{0} ** 7,
    _3: u80 = 0,
    iobp_offset: u16 = 104,
    bitset: [8192]u8 = [1]u8{0} ** 8192,

    pub noinline fn init(self: *@This()) void {
        @memset(@intToPtr([*]u8, @ptrToInt(self)), 0, @sizeOf(@This()));
        self.iobp_offset = 104;
    }
 
    pub fn set_interrupt_stack(self: *@This(), stack: usize) void {
        self.ist[0] = stack;
    }

    pub fn set_scheduler_stack(self: *@This(), stack: usize) void {
        self.ist[1] = stack;
    }
 
    pub fn set_syscall_stack(self: *@This(), stack: usize) void {
        self.rsp[0] = stack;
    }
};
