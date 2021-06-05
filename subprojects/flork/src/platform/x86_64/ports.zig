usingnamespace @import("root").preamble;

pub fn out(comptime T: type, port: u16, value: T) void {
    switch (T) {
        u8 => outb(port, value),
        u16 => outw(port, value),
        u32 => outl(port, value),
        else => @compileError("No out instruction for this type"),
    }
}

pub fn in(comptime T: type, port: u16) T {
    return switch (T) {
        u8 => inb(port),
        u16 => inw(port),
        u32 => inl(port),
        else => @compileError("No in instruction for this type"),
    };
}

pub fn outb(port: u16, val: u8) void {
    asm volatile ("outb %[val], %[port]\n\t"
        :
        : [val] "{al}" (val),
          [port] "N{dx}" (port)
    );
}

pub fn outw(port: u16, val: u16) void {
    asm volatile ("outw %[val], %[port]\n\t"
        :
        : [val] "{ax}" (val),
          [port] "N{dx}" (port)
    );
}

pub fn outl(port: u16, val: u32) void {
    asm volatile ("outl %[val], %[port]\n\t"
        :
        : [val] "{eax}" (val),
          [port] "N{dx}" (port)
    );
}

pub fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]\n\t"
        : [result] "={al}" (-> u8)
        : [port] "N{dx}" (port)
    );
}

fn inw(port: u16) u16 {
    return asm volatile ("inw %[port], %[result]\n\t"
        : [result] "={ax}" (-> u16)
        : [port] "N{dx}" (port)
    );
}

pub fn inl(port: u16) u32 {
    return asm volatile ("inl %[port], %[result]\n\t"
        : [result] "={eax}" (-> u32)
        : [port] "N{dx}" (port)
    );
}

export fn laihost_outb(port: u16, value: u8) void {
    outb(port, value);
}
export fn laihost_outw(port: u16, value: u16) void {
    outw(port, value);
}
export fn laihost_outd(port: u16, value: u32) void {
    outl(port, value);
}

export fn laihost_inb(port: u16) u8 {
    return inb(port);
}
export fn laihost_inw(port: u16) u16 {
    return inw(port);
}
export fn laihost_ind(port: u16) u32 {
    return inl(port);
}
