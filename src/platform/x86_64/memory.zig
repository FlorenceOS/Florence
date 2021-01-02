const os = @import("root").os;

pub const physaddr_bits = 51;
pub const page_offset_bits = 12;

pub const paging_levels = 5;
pub const virt_bits = page_offset_bits + 9 * paging_levels;
