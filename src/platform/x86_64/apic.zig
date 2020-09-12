const acpi = @import("../acpi.zig");

const log = @import("../../logger.zig").log;

const MADT = struct {
  sdt: acpi.SDT,
};

pub fn handle_madt(ptr: *acpi.SDT) void {
  const madt = @ptrCast(*MADT, ptr);
  log("APIC: Got MADT!\n", .{});
}
