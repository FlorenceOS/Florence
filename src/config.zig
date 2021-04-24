pub const kernel = .{
  .max_cpus = 0x200,
  
  .x86_64 = .{
    .allow_syscall_instr = true,
  },
};
