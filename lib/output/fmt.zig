const std = @import("std");

const hex_print_bits = 64;
const hex_print_t = std.meta.Int(.unsigned, hex_print_bits);
const hex_print_nibbles = @divExact(hex_print_bits, 4);

const printCharacter = @import("root").putchar;

// zig fmt freaks out when it sees `noinline` for some reason(?)
// zig fmt: off
noinline fn printString(str: [*:0]const u8) void {
    if (str[0] != 0) {
        printCharacter(str[0]);
        return @call(.{ .modifier = .always_tail }, printString, .{str + 1});
    }
}

const hex_chars: [*]const u8 = "0123456789ABCDEF";

noinline fn printRuntimeValueAsZeroPaddedHex(val: hex_print_t) void {
    comptime var i: u6 = hex_print_nibbles - 1;
    inline while (true) : (i -= 1) {
        const v = @truncate(u4, val >> (4 * i));

        printCharacter(hex_chars[v]);

        if (i == 0)
            break;
    }
}

fn comptimeValToZeroPaddedHexString(in_val: anytype) [hex_print_nibbles]u8 {
    const val = @intCast(hex_print_t, in_val);

    var i: u6 = 0;
    var result: [hex_print_nibbles]u8 = undefined;
    while (i < hex_print_nibbles) : (i += 1) {
        result[i] = hex_chars[@truncate(u4, val >> ((hex_print_nibbles - i - 1) * 4))];
    }
    return result;
}

fn formatMatches(fmt: []const u8, idx: usize, to_match: []const u8) callconv(.Inline) bool {
    const curr_fmt = fmt[idx..];
    return std.mem.startsWith(u8, curr_fmt, to_match);
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
        printString(str.ptr);
    }
}

noinline fn defaultFormatStruct(value: anytype) void {
    const treat_as_type = switch(@typeInfo(@TypeOf(value.*))) {
        .Pointer => @TypeOf(value.*.*),
        else => @TypeOf(value.*),
    };

    switch(@typeInfo(treat_as_type)) {
        .Struct => |info| {
            const arg_fields = info.fields;
            
            comptime var current_fmt: [:0]const u8 = @typeName(@TypeOf(value.*)) ++ "{{ ";

            inline for (arg_fields) |field, i| {
                switch (@typeInfo(field.field_type)) {
                    .Int => doFmtNoEndl(current_fmt ++ "." ++ field.name ++ " = {d}", .{@field(value.*, field.name)}),
                    .Struct => doFmtNoEndl(current_fmt ++ "." ++ field.name ++ " = {}", .{@field(value.*, field.name)}),
                    else => @compileError("No idea how to format this struct field type: '" ++ @typeName(field.field_type) ++ "' (while processing type '" ++ @typeName(treat_as_type) ++ "')!"),
                }
                current_fmt = if (i == current_fmt.len - 1) "" else ", ";
            }

            current_fmt = current_fmt ++ " }}";

            doFmtNoEndl(current_fmt, .{});
        },
        .Optional => |opt| {
            if(value.*) |v| {
                doFmtNoEndl("{}", .{v});
            } else {
                doFmtNoEndl("null", .{});
            }
        },
        else => @compileError("Bad type '" ++ @typeName(treat_as_type) ++ "' for struct fmt!"),
    }
}

pub fn doFmtNoEndl(comptime fmt: []const u8, args: anytype) void {
    comptime var fmt_idx = 0;
    comptime var arg_idx = 0;
    comptime var current_str: [:0]const u8 = "";

    const arg_fields = @typeInfo(@TypeOf(args)).Struct.fields;

    @setEvalBranchQuota(9999999);

    inline while (fmt_idx < fmt.len) {
        if (comptime formatMatches(fmt, fmt_idx, "{{")) {
            current_str = current_str ++ [_]u8{'{'};
            fmt_idx += 2;
        } else if (comptime formatMatches(fmt, fmt_idx, "}}")) {
            current_str = current_str ++ [_]u8{'}'};
            fmt_idx += 2;
        } else if (comptime formatMatches(fmt, fmt_idx, "{0X}")) {
            const value = @field(args, arg_fields[arg_idx].name);
            if (arg_fields[arg_idx].is_comptime) {
                current_str = current_str ++ comptime comptimeValToZeroPaddedHexString(value);
            } else {
                printString(current_str.ptr);
                current_str = "";
                printRuntimeValueAsZeroPaddedHex(value);
            }
            fmt_idx += 4;
            arg_idx += 1;
        } else if (comptime formatMatches(fmt, fmt_idx, "{X}")) {
            const value = @field(args, arg_fields[arg_idx].name);
            if (arg_fields[arg_idx].is_comptime) {
                current_str = current_str ++ comptime comptimeValToString(value, 16);
            } else {
                printString(current_str.ptr);
                current_str = "";
                printRuntimeValue(value, 16);
            }
            fmt_idx += 3;
            arg_idx += 1;
        } else if (comptime formatMatches(fmt, fmt_idx, "{d}")) {
            const value = @field(args, arg_fields[arg_idx].name);
            if (arg_fields[arg_idx].is_comptime) {
                current_str = current_str ++ comptime comptimeValToString(value, 10);
            } else {
                printString(current_str.ptr);
                current_str = "";
                printRuntimeValue(value, 10);
            }
            fmt_idx += 3;
            arg_idx += 1;
        } else if (comptime formatMatches(fmt, fmt_idx, "{e}")) {
            const value = @field(args, arg_fields[arg_idx].name);

            switch (@typeInfo(@TypeOf(value))) {
                .Enum => current_str = current_str ++ @typeName(@TypeOf(value)),
                else => {},
            }
            current_str = current_str ++ ".";

            if (arg_fields[arg_idx].is_comptime) {
                current_str = current_str ++ comptime @tagName(value);
            } else {
                printString(current_str.ptr);
                current_str = "";
                printString(@tagName(value));
            }
            fmt_idx += 3;
            arg_idx += 1;
        } else if (comptime formatMatches(fmt, fmt_idx, "{s}")) {
            const value = @field(args, arg_fields[arg_idx].name);
            if (arg_fields[arg_idx].is_comptime) {
                current_str = current_str ++ comptime value;
            } else {
                printString(current_str.ptr);
                current_str = "";
                // TODO: Different paths depending on the string type: [*:0]const u8, []const u8, ...
                // For now we just assume [*:0]const u8
                printString(value);
            }
            fmt_idx += 3;
            arg_idx += 1;
        } else if (comptime formatMatches(fmt, fmt_idx, "{c}")) {
            const value = @field(args, arg_fields[arg_idx].name);
            if (arg_fields[arg_idx].is_comptime) {
                current_str = current_str ++ comptime [_]u8{value};
            } else {
                printString(current_str.ptr);
                current_str = "";
                printCharacter(value);
            }
            fmt_idx += 3;
            arg_idx += 1;
        } else if (comptime formatMatches(fmt, fmt_idx, "{}")) {
            printString(current_str.ptr);
            current_str = "";

            const value = @field(args, arg_fields[arg_idx].name);
            switch(@typeInfo(@TypeOf(value))) {
                .Struct, .Enum, .Union => {
                    if (comptime @hasDecl(@TypeOf(value), "format")) {
                        @call(.{ .modifier = .never_inline }, value.format, .{doFmtNoEndl});
                    } else {
                        defaultFormatStruct(&value);
                    }
                },
                else => defaultFormatStruct(&value),
            }
            
            fmt_idx += 2;
            arg_idx += 1;
        } else if (comptime formatMatches(fmt, fmt_idx, "{")) {
            @compileError("Unknown format specifier: '" ++ [_]u8{fmt[fmt_idx + 1]} ++ "'");
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
