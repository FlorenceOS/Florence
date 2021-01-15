// All decoded PTEs have to become one of these types.

pub const PTEType = enum {
  Mapping,
  Table,
  Empty  
};
