const os = @import("root").os;
const std = @import("std");

pub const paging = @import("paging.zig");
pub const thread = @import("thread.zig");

const pmm       = os.memory.pmm;
const bf        = os.lib.bitfields;

const assert = std.debug.assert;

pub fn msr(comptime T: type, comptime name: []const u8) type {
  return struct {
    pub fn read() T {
      return asm volatile(
        "MRS %[out], " ++ name
        : [out]"=r"(-> T)
      );
    }

    pub fn write(val: T) void {
      asm volatile(
        "MSR " ++ name ++ ", %[in]"
        :
        : [in]"r"(val)
      );
    }
  };
}

pub fn spin_hint() void {
  asm volatile("YIELD");
}

pub fn allowed_mapping_levels() usize {
  return 2;
}

pub fn platform_init() !void {
  try os.platform.acpi.init_acpi();
  try os.platform.pci.init_pci();
  os.log("The platform is alive!\n", .{});
}

pub fn ap_init() void {
  os.memory.paging.kernel_context.apply();
}

pub fn debugputch(val: u8) void {

}

pub const InterruptState = bool;

pub fn get_and_disable_interrupts() InterruptState {
  // Get interrupt mask flag
  var daif = asm volatile("MRS %[daif_val], DAIF" : [daif_val] "=r" (-> u64));

  // Set the flag
  asm volatile("MSR DAIFSET, 2" ::: "memory");
  
  // Check if it was set
  return (daif >> 7) & 1 == 0;
}

pub fn set_interrupts(s: InterruptState) void {
  if(s) {
    // Enable interrupts
    asm volatile("MSR DAIFCLR, 2" ::: "memory");
  } else {
    // Disable interrupts
    asm volatile("MSR DAIFSET, 2" ::: "memory");
  }
}

pub const InterruptFrame = struct {
  mode: u64,
  _: u64,
  x31: u64,
  x30: u64,
  x29: u64,
  x28: u64,
  x27: u64,
  x26: u64,
  x25: u64,
  x24: u64,
  x23: u64,
  x22: u64,
  x21: u64,
  x20: u64,
  x19: u64,
  x18: u64,
  x17: u64,
  x16: u64,
  x15: u64,
  x14: u64,
  x13: u64,
  x12: u64,
  x11: u64,
  x10: u64,
  x9: u64,
  x8: u64,
  x7: u64,
  x6: u64,
  x5: u64,
  x4: u64,
  x3: u64,
  x2: u64,
  x1: u64,
  x0: u64,
};

export fn interrupt64_common() callconv(.Naked) void {
  asm volatile(
    \\STP X1,  X0,  [SP, #-0x10]!
    \\STP X3,  X2,  [SP, #-0x10]!
    \\STP X5,  X4,  [SP, #-0x10]!
    \\STP X7,  X6,  [SP, #-0x10]!
    \\STP X9,  X8,  [SP, #-0x10]!
    \\STP X11, X10, [SP, #-0x10]!
    \\STP X13, X12, [SP, #-0x10]!
    \\STP X15, X14, [SP, #-0x10]!
    \\STP X17, X16, [SP, #-0x10]!
    \\STP X19, X18, [SP, #-0x10]!
    \\STP X21, X20, [SP, #-0x10]!
    \\STP X23, X22, [SP, #-0x10]!
    \\STP X25, X24, [SP, #-0x10]!
    \\STP X27, X26, [SP, #-0x10]!
    \\STP X29, X28, [SP, #-0x10]!
    \\STP X31, X30, [SP, #-0x10]!
    \\MOV X0, #64
    \\STP X0,  XZR, [SP, #-0x10]!
    \\MOV X0,  SP
    \\BL interrupt64_handler
    \\LDP XZR, XZR, [SP], 0x10
    \\LDP X31, X30, [SP], 0x10
    \\LDP X29, X28, [SP], 0x10
    \\LDP X27, X26, [SP], 0x10
    \\LDP X25, X24, [SP], 0x10
    \\LDP X23, X22, [SP], 0x10
    \\LDP X21, X20, [SP], 0x10
    \\LDP X19, X18, [SP], 0x10
    \\LDP X17, X16, [SP], 0x10
    \\LDP X15, X14, [SP], 0x10
    \\LDP X13, X12, [SP], 0x10
    \\LDP X11, X10, [SP], 0x10
    \\LDP X9,  X8,  [SP], 0x10
    \\LDP X7,  X6,  [SP], 0x10
    \\LDP X5,  X4,  [SP], 0x10
    \\LDP X3,  X2,  [SP], 0x10
    \\LDP X1,  X0,  [SP], 0x10
    \\ERET
  );
}

export fn interrupt32_common() callconv(.Naked) void {
  asm volatile(
    \\STP W0,  WZR, [SP, #-0x8]!
    \\STP W1,  WZR, [SP, #-0x8]!
    \\STP W2,  WZR, [SP, #-0x8]!
    \\STP W3,  WZR, [SP, #-0x8]!
    \\STP W4,  WZR, [SP, #-0x8]!
    \\STP W5,  WZR, [SP, #-0x8]!
    \\STP W6,  WZR, [SP, #-0x8]!
    \\STP W7,  WZR, [SP, #-0x8]!
    \\STP W8,  WZR, [SP, #-0x8]!
    \\STP W9,  WZR, [SP, #-0x8]!
    \\STP W10, WZR, [SP, #-0x8]!
    \\STP W11, WZR, [SP, #-0x8]!
    \\STP W12, WZR, [SP, #-0x8]!
    \\STP W13, WZR, [SP, #-0x8]!
    \\STP W14, WZR, [SP, #-0x8]!
    \\STP W15, WZR, [SP, #-0x8]!
    \\STP XZR, XZR, [SP, #-0x10]! // 16, 17
    \\STP XZR, XZR, [SP, #-0x10]! // 18, 19
    \\STP XZR, XZR, [SP, #-0x10]! // 20, 21
    \\STP XZR, XZR, [SP, #-0x10]! // 22, 23
    \\STP XZR, XZR, [SP, #-0x10]! // 24, 25
    \\STP XZR, XZR, [SP, #-0x10]! // 26, 27
    \\STP XZR, XZR, [SP, #-0x10]! // 28, 29
    \\STP XZR, XZR, [SP, #-0x10]! // 30, 31
    \\MOV X0, #64
    \\STP X0,  XZR, [SP, #-0x10]!
    \\MOV X0,  SP
    \\BL interrupt32_handler
    \\ADD SP,  SP,  0x80 // 16 - 31
    \\LDP W15, WZR, [SP], 0x8
    \\LDP W14, WZR, [SP], 0x8
    \\LDP W13, WZR, [SP], 0x8
    \\LDP W12, WZR, [SP], 0x8
    \\LDP W11, WZR, [SP], 0x8
    \\LDP W10, WZR, [SP], 0x8
    \\LDP W9,  WZR, [SP], 0x8
    \\LDP W8,  WZR, [SP], 0x8
    \\LDP W7,  WZR, [SP], 0x8
    \\LDP W6,  WZR, [SP], 0x8
    \\LDP W5,  WZR, [SP], 0x8
    \\LDP W4,  WZR, [SP], 0x8
    \\LDP W3,  WZR, [SP], 0x8
    \\LDP W2,  WZR, [SP], 0x8
    \\LDP W1,  WZR, [SP], 0x8
    \\LDP W0,  WZR, [SP], 0x8
    \\RET
  );
}

comptime {
  asm(
    \\.section .text.evt
    \\.balign 0x800
    \\.global exception_vector_table; exception_vector_table:
    \\.balign 0x80; B interrupt64_common // curr_el_sp0_sync
    \\.balign 0x80; B interrupt64_common // curr_el_sp0_irq
    \\.balign 0x80; B interrupt64_common // curr_el_sp0_fiq
    \\.balign 0x80; B interrupt64_common // curr_el_sp0_serror
    \\.balign 0x80; B interrupt64_common // curr_el_spx_sync
    \\.balign 0x80; B interrupt64_common // curr_el_spx_irq
    \\.balign 0x80; B interrupt64_common // curr_el_spx_fiq
    \\.balign 0x80; B interrupt64_common // curr_el_spx_serror
    \\.balign 0x80; B interrupt64_common // lower_el_aarch64_sync
    \\.balign 0x80; B interrupt64_common // lower_el_aarch64_irq
    \\.balign 0x80; B interrupt64_common // lower_el_aarch64_fiq
    \\.balign 0x80; B interrupt64_common // lower_el_aarch64_serror
    \\.balign 0x80; B interrupt32_common // lower_el_aarch32_sync
    \\.balign 0x80; B interrupt32_common // lower_el_aarch32_irq
    \\.balign 0x80; B interrupt32_common // lower_el_aarch32_fiq
    \\.balign 0x80; B interrupt32_common // lower_el_aarch32_serror
  );
}

extern const exception_vector_table: [0x800]u8;

pub fn platform_early_init() void {
  os.platform.smp.prepare();
  install_vector_table();
  os.memory.paging.init();
}

pub fn install_vector_table() void {
  os.log("Installing exception vector table at 0x{X}\n", .{@ptrToInt(&exception_vector_table[0])});
  asm volatile(
    \\MSR VBAR_EL1, %[evt]
    :
    : [evt] "r" (&exception_vector_table)
  );
}

pub fn await_interrupt() void {
  asm volatile(
    \\ MSR DAIFCLR, 0xF
    \\ WFI
    \\ MSR DAIFSET, 0xF
    :
    :
    : "memory"
  );
}

export fn interrupt64_handler(frame: *InterruptFrame) void {
  const esr = asm volatile("MRS %[esr], ESR_EL1" : [esr] "=r" (-> u64));

  const ec = (esr >> 26) & 0x3f;
  const iss = esr & 0x1ffffff;

  if(ec == 0b111100) {
    os.log("BRK instruction execution in AArch64 state\n", .{});
    os.platform.hang();
  }

  switch(ec) {
    else => @panic("Unknown EC!"),
    0b00000000 => @panic("Unknown reason in EC!"),
    0b00100101 => @panic("Data abort without change in exception level"),
    0b00100001 => @panic("Instruction fault without change in exception level"),
    0b00010101 => {
      // SVC instruction execution in AArch64 state
      // Figure out which call this is

      switch(@truncate(u16, iss)) {
        else => @panic("Unknown SVC"),

        'Y' => @panic("yield_to_task"),
      }
    },
  }
}

export fn interrupt32_handler(frame: *InterruptFrame) void {
  @panic("Got a 32 bit interrupt or something idk");
}

pub fn prepare_paging() !void {

}
