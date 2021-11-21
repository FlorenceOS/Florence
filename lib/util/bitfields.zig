const std = @import("std");

fn PtrCastPreserveCV(comptime T: type, comptime PtrToT: type, comptime NewT: type) type {
    return switch (PtrToT) {
        *T => *NewT,
        *const T => *const NewT,
        *volatile T => *volatile NewT,
        *const volatile T => *const volatile NewT,

        else => @compileError("wtf you doing"),
    };
}

fn BitType(comptime FieldType: type, comptime ValueType: type, comptime shamt: usize) type {
    const self_bit: FieldType = (1 << shamt);

    return struct {
        bits: Bitfield(FieldType, shamt, 1),

        pub fn set(self: anytype) void {
            self.bits.field().* |= self_bit;
        }

        pub fn unset(self: anytype) void {
            self.bits.field().* &= ~self_bit;
        }

        pub fn read(self: anytype) ValueType {
            return @bitCast(ValueType, @truncate(u1, self.bits.field().* >> shamt));
        }

        // Since these are mostly used with MMIO, I want to avoid
        // reading the memory just to write it again, also races
        pub fn write(self: anytype, val: ValueType) void {
            if (@bitCast(bool, val)) {
                self.set();
            } else {
                self.unset();
            }
        }
    };
}

pub fn Bit(comptime FieldType: type, comptime shamt: usize) type {
    return BitType(FieldType, u1, shamt);
}

pub fn Boolean(comptime FieldType: type, comptime shamt: usize) type {
    return BitType(FieldType, bool, shamt);
}

pub fn Bitfield(comptime FieldType: type, comptime shamt: usize, comptime num_bits: usize) type {
    if (shamt + num_bits > @bitSizeOf(FieldType)) {
        @compileError("bitfield doesn't fit");
    }

    const self_mask: FieldType = ((1 << num_bits) - 1) << shamt;

    const ValueType = std.meta.Int(.unsigned, num_bits);

    return struct {
        dummy: FieldType,

        fn field(self: anytype) PtrCastPreserveCV(@This(), @TypeOf(self), FieldType) {
            return @ptrCast(PtrCastPreserveCV(@This(), @TypeOf(self), FieldType), self);
        }

        pub fn write(self: anytype, val: ValueType) void {
            self.field().* &= ~self_mask;
            self.field().* |= @intCast(FieldType, val) << shamt;
        }

        pub fn read(self: anytype) ValueType {
            const val: FieldType = self.field().*;
            return @intCast(ValueType, (val & self_mask) >> shamt);
        }
    };
}

test "bit" {
    const S = extern union {
        low: Bit(u32, 0),
        high: Bit(u32, 1),
        val: u32,
    };

    std.testing.expect(@sizeOf(S) == 4);
    std.testing.expect(@bitSizeOf(S) == 32);

    var s: S = .{ .val = 1 };

    std.testing.expect(s.low.read() == 1);
    std.testing.expect(s.high.read() == 0);

    s.low.write(0);
    s.high.write(1);

    std.testing.expect(s.val == 2);
}

test "boolean" {
    const S = extern union {
        low: Boolean(u32, 0),
        high: Boolean(u32, 1),
        val: u32,
    };

    std.testing.expect(@sizeOf(S) == 4);
    std.testing.expect(@bitSizeOf(S) == 32);

    var s: S = .{ .val = 2 };

    std.testing.expect(s.low.read() == false);
    std.testing.expect(s.high.read() == true);

    s.low.write(true);
    s.high.write(false);

    std.testing.expect(s.val == 1);
}

test "bitfield" {
    const S = extern union {
        low: Bitfield(u32, 0, 16),
        high: Bitfield(u32, 16, 16),
        val: u32,
    };

    std.testing.expect(@sizeOf(S) == 4);
    std.testing.expect(@bitSizeOf(S) == 32);

    var s: S = .{ .val = 0x13376969 };

    std.testing.expect(s.low.read() == 0x6969);
    std.testing.expect(s.high.read() == 0x1337);

    s.low.write(0x1337);
    s.high.write(0x6969);

    std.testing.expect(s.val == 0x69691337);
}
