const std = @import("std");

const hex_print_bits = 64;
const hex_print_t = std.meta.Int(.unsigned, hex_print_bits);
const hex_print_nibbles = @divExact(hex_print_bits, 4);

const printCharacter = @import("root").putchar;

// zig fmt freaks out when it sees `noinline` for some reason(?)
// zig fmt: off
noinline fn printSentinelString(str_c: [*:0]const u8) void {
    var str = str_c;
    while (str[0] != 0) : (str += 1) {
        printCharacter(str[0]);
    }
}

noinline fn printSliceString(str: []const u8) void {
    for(str) |c| {
        printCharacter(c);
    }
}

noinline fn printPointerInt(ptr: usize) void {
    printSentinelString("0x");
    printRuntimeValueAsZeroPaddedHex(ptr);
}

fn printPointer(ptr: anytype) callconv(.Inline) void {
    printPointerInt(@ptrToInt(ptr));
}

const boolean_names = [2][*:0]const u8 {
    "false",
    "true",
};

noinline fn printBoolean(value: bool) void {
    printSentinelString(boolean_names[@boolToInt(value)]);
}

const hex_chars: [*]const u8 = "0123456789ABCDEF";

noinline fn printRuntimeValueAsZeroPaddedHex(val_in: anytype) void {
    // Make it large enough for hex printing
    const val = if(@bitSizeOf(@TypeOf(val_in)) < 4)
        @as(u4, val_in)
    else
        val_in;

    comptime var i: u6 = @divFloor(@bitSizeOf(@TypeOf(val)) + 3, 4) - 1;
    inline while (true) : (i -= 1) {
        const v = @truncate(u4, val >> (4 * i));

        printCharacter(hex_chars[v]);

        if (i == 0)
            break;
    }
}

fn comptimeValToZeroPaddedHexString(val: anytype) [@sizeOf(@TypeOf(val))*2:0]u8 {
    const numNibbles = @sizeOf(@TypeOf(val))*2;

    var i: u6 = 0;
    var result: [numNibbles:0]u8 = undefined;
    result[numNibbles] = 0;
    while (i < numNibbles) : (i += 1) {
        result[i] = hex_chars[@truncate(u4, val >> ((numNibbles - i - 1) * 4))];
    }
    return result;
}

fn lengthOfIntAsString(num: anytype, comptime base: comptime_int) usize {
    if (num < base)
        return 1;
    const rest = num / base;
    return lengthOfIntAsString(rest, base) + 1;
}

fn comptimeValToString(val: anytype, comptime base: comptime_int) [lengthOfIntAsString(val, base)]u8 {
    const current = hex_chars[val % base];
    const rest = val / base;
    if (rest == 0)
        return [_]u8{current};
    return comptimeValToString(rest, base) ++ [_]u8{current};
}

noinline fn printRuntimeValue(val: usize, comptime base: comptime_int) void {
    const rest = val / base;
    if (rest != 0)
        printRuntimeValue(rest, base);
    return printCharacter(hex_chars[val % base]);
}

fn putComptimeStr(comptime str: [:0]const u8) callconv(.Inline) void {
    if (comptime (str.len == 1)) {
        printCharacter(str[0]);
    }
    if (comptime (str.len > 1)) {
        printSentinelString(str.ptr);
    }
}

fn defaultFormatValue(value: anytype, comptime fmt_so_far: [:0]const u8) callconv(.Inline) void {
    switch(@typeInfo(@TypeOf(value.*))) {
        .Struct => {
            if (comptime @hasDecl(@TypeOf(value.*), "format")) {
                putComptimeStr(fmt_so_far);
                value.format(doFmtNoEndl);
            } else {
                putComptimeStr(defaultFormatStruct(value, fmt_so_far));
            }
        },
        .Enum, .Union => {
            if (comptime @hasDecl(@TypeOf(value.*), "format")) {
                putComptimeStr(fmt_so_far);
                value.format(doFmtNoEndl);
            } else {
                @compileError("Cannot format '" ++ @typeName(@TypeOf(value.*)) ++ "' yet");
            }
        },
        .Pointer => {
            defaultFormatValue(value.*, fmt_so_far);
        },
        .Optional => {
            putComptimeStr(fmt_so_far);
            // Runtime if, flush before!
            if(value.* != null) {
                defaultFormatValue(&(value.*.?), "");
            } else {
                putComptimeStr("null");
            }
        },

        else => @compileError("Type '" ++ @typeName(@TypeOf(value.*)) ++ "' not available for {}-formatting"),
    }
}

noinline fn defaultFormatStruct(value: anytype, comptime fmt_so_far: []const u8) [:0]const u8 {
    const arg_fields = @typeInfo(@TypeOf(value.*)).Struct.fields;
            
    comptime var current_fmt: [:0]const u8 = fmt_so_far ++ @typeName(@TypeOf(value.*)) ++ "{{ ";

    inline for (arg_fields) |field, i| {
        const trailing = defaultFormatValue(&@field(value.*, field.name), current_fmt ++ "." ++ field.name ++ " = ");
        current_fmt = trailing ++ if (i == current_fmt.len - 1) "" else ", ";
    }

    return current_fmt ++ " }}";
}

pub fn doFmtNoEndl(comptime fmt: []const u8, args: anytype) void {
    comptime var fmt_idx = 0;
    comptime var arg_idx = 0;
    comptime var current_str: [:0]const u8 = "";

    const arg_fields = @typeInfo(@TypeOf(args)).Struct.fields;

    @setEvalBranchQuota(9999999);

    inline while (fmt_idx < fmt.len) {
        if (fmt[fmt_idx] == '}') { // }}
            current_str = current_str ++ [_]u8{'}'};
            fmt_idx += 2;
        } else if(fmt[fmt_idx] == '{') {
            if (fmt[fmt_idx + 1] == '{') { // {{
                current_str = current_str ++ [_]u8{'{'};
                fmt_idx += 2;
            } else if (fmt[fmt_idx + 1] == '0' and fmt[fmt_idx + 2] == 'X') {
                const value = &@field(args, arg_fields[arg_idx].name);
                if (arg_fields[arg_idx].is_comptime) {
                    current_str = current_str ++ comptime comptimeValToZeroPaddedHexString(value.*);
                } else {
                    putComptimeStr(current_str);
                    current_str = "";
                    printRuntimeValueAsZeroPaddedHex(value.*);
                }
                fmt_idx += 4;
                arg_idx += 1;
            } else if (fmt[fmt_idx + 1] == 'X') { // {X}
                const value = &@field(args, arg_fields[arg_idx].name);
                if (arg_fields[arg_idx].is_comptime) {
                    current_str = current_str ++ comptime comptimeValToString(value.*, 16);
                } else {
                    putComptimeStr(current_str);
                    current_str = "";
                    printRuntimeValue(value.*, 16);
                }
                fmt_idx += 3;
                arg_idx += 1;
            } else if (fmt[fmt_idx + 1] == 'd') { // {d}
                const value = &@field(args, arg_fields[arg_idx].name);
                if (arg_fields[arg_idx].is_comptime) {
                    current_str = current_str ++ comptime comptimeValToString(value.*, 10);
                } else {
                    putComptimeStr(current_str);
                    current_str = "";
                    printRuntimeValue(value.*, 10);
                }
                fmt_idx += 3;
                arg_idx += 1;
            } else if (fmt[fmt_idx + 1] == 'e') { // {e}
                const value = &@field(args, arg_fields[arg_idx].name);

                switch (@typeInfo(@TypeOf(value.*))) {
                    .Enum, .ErrorSet => current_str = current_str ++ @typeName(@TypeOf(value.*)),
                    else => {},
                }
                current_str = current_str ++ ".";

                if (arg_fields[arg_idx].is_comptime) {
                    switch(@typeInfo(@TypeOf(value.*))) {
                        .Enum => current_str = current_str ++ comptime @tagName(value.*),
                        .ErrorSet => current_str = current_str ++ comptime @errorName(value.*),
                        else => @compileError("Cannot format type '" ++ @typeName(@TypeOf(value.*)) ++ "' with {e}."),
                    }
                } else {
                    putComptimeStr(current_str);
                    current_str = "";
                    switch(@typeInfo(@TypeOf(value.*))) {
                        // switch to printSentinelString once we have in our compiler build https://github.com/ziglang/zig/pull/8636
                        .Enum => printSliceString(@tagName(value.*)),
                        .ErrorSet => printSliceString(@errorName(value.*)),
                        else => @compileError("Cannot format type '" ++ @typeName(@TypeOf(value.*)) ++ "' with {e}."),
                    }
                }
                fmt_idx += 3;
                arg_idx += 1;
            } else if (fmt[fmt_idx + 1] == 's') { // {s}
                const value = &@field(args, arg_fields[arg_idx].name);
                if (arg_fields[arg_idx].is_comptime) {
                    current_str = current_str ++ comptime value.*;
                } else {
                    putComptimeStr(current_str);
                    current_str = "";
                    switch(@TypeOf(value.*)) {
                        [*:0]u8, [*:0]const u8 => printSentinelString(value.*),
                        [:0]u8, [:0]const u8 => printSentinelString(value.ptr),
                        []u8, []const u8 => printSliceString(value.*),
                        else => @compileError("Bad type " ++ @typeName(@TypeOf(value.*)) ++ " for {s} formatting"),
                    }
                }
                fmt_idx += 3;
                arg_idx += 1;
            } else if (fmt[fmt_idx + 1] == 'c') { // {c}
                const value = &@field(args, arg_fields[arg_idx].name);
                if (arg_fields[arg_idx].is_comptime) {
                    current_str = current_str ++ comptime [_]u8{value.*};
                } else {
                    putComptimeStr(current_str);
                    current_str = "";
                    printCharacter(value.*);
                }
                fmt_idx += 3;
                arg_idx += 1;
            } else if (fmt[fmt_idx + 1] == 'b') { // {b}
                const value = &@field(args, arg_fields[arg_idx].name);
                if (arg_fields[arg_idx].is_comptime) {
                    current_str = current_str ++ if(value.*) "true" else "false";
                } else {
                    putComptimeStr(current_str);
                    current_str = "";
                    printBoolean(value.*);
                }
                fmt_idx += 3;
                arg_idx += 1;
            } else if (fmt[fmt_idx + 1] == '*') { // {*}
                const value = &@field(args, arg_fields[arg_idx].name);
                putComptimeStr(current_str);
                current_str = "";
                printPointer(value.*);
                fmt_idx += 3;
                arg_idx += 1;
            } else if (fmt[fmt_idx + 1] == '}') { // {}
                defaultFormatValue(&@field(args, arg_fields[arg_idx].name), current_str);
                current_str = "";
                fmt_idx += 2;
                arg_idx += 1;
            } else {
                @compileError("Unknown format specifier: '" ++ [_]u8{fmt[fmt_idx + 1]} ++ "'");
            }
        } else {
            current_str = current_str ++ [_]u8{fmt[fmt_idx]};
            fmt_idx += 1;
        }
    }

    putComptimeStr(current_str);

    if (arg_idx < arg_fields.len) {
        @compileError("Unused fmt arguments!");
    }
}

pub fn doFmt(comptime fmt: []const u8, args: anytype) callconv(.Inline) void {
    return doFmtNoEndl(fmt ++ "\n", args);
}
