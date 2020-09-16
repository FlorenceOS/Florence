const acpi = @import("../acpi.zig");

const log = @import("../../logger.zig").log;

pub fn handle_madt(madt: []u8) void {
  log("APIC: Got MADT!\n", .{});
}
