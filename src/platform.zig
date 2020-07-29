const arch = @import("builtin").arch;

usingnamespace @import(
  if(arch == .aarch64) "platform/aarch64/aarch64.zig" else
  if(arch == .x86_64)  "platform/x86_64/x86_64.zig" else
  unreachable
);
