const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;

fn RingBuffer(comptime T: type) type {
    return struct {
        buffer: []T,
        head: usize,
        tail: usize,
        last_action: enum { Add, Remove },

        pub fn init(buffer: []T) @This() {
            return .{
                .buffer = buffer,
                .head = 0,
                .tail = 0,
                .last_action = .Remove,
            };
        }

        pub fn next(self: *@This()) void {
            std.debug.assert(!self.is_empty());
            self.tail = (self.tail + 1) % self.buffer.len;
            self.last_action = .Remove;
        }

        pub fn skip(self: *@This(), count: usize) void {
            std.debug.assert(count <= self.used_size());
            self.tail = (self.tail + count) % self.buffer.len;
            if (count != 0) {
                self.last_action = .Remove;
            }
        }

        pub fn read_ahead(self: *const @This()) T {
            std.debug.assert(!self.is_empty());
            return self.buffer[self.tail];
        }

        pub fn read_ahead_at(self: *const @This(), index: usize) T {
            std.debug.assert(index < self.used_size());
            return self.buffer[(self.tail + index) % self.buffer.len];
        }

        pub fn read_ahead_slice(self: *const @This(), slice: []T) void {
            std.debug.assert(slice.len <= self.used_size());
            for (slice) |*ref, i| {
                ref.* = self.read_ahead_at(i);
            }
        }

        pub fn push(self: *@This(), elem: T) void {
            std.debug.assert(!self.is_full());
            self.buffer[self.head] = elem;
            self.head = (self.head + 1) % self.buffer.len;
            self.last_action = .Add;
        }

        pub fn pop(self: *@This()) T {
            std.debug.assert(!self.is_empty());
            var result: T = self.buffer[self.tail];
            self.next();
            return result;
        }

        pub fn push_slice(self: *@This(), slice: []const T) void {
            std.debug.assert(slice.len <= self.free_size());
            for (slice) |value| {
                self.push(value);
            }
        }

        pub fn pop_slice(self: *@This(), slice: []T) void {
            std.debug.assert(slice.len <= self.used_size());
            self.read_ahead_slice(slice);
            self.skip(slice.len);
        }

        pub fn used_size(self: *const @This()) usize {
            if (self.head > self.tail) {
                return self.head - self.tail;
            } else if (self.head < self.tail) {
                return (self.head + self.buffer.len) - self.tail;
            } else if (self.last_action == .Remove) {
                return 0;
            } else {
                return self.buffer.len;
            }
        }

        pub fn free_size(self: *const @This()) usize {
            return self.buffer.len - self.used_size();
        }

        pub fn is_empty(self: *const @This()) bool {
            return self.used_size() == 0;
        }

        pub fn is_full(self: *const @This()) bool {
            return self.free_size() == 0;
        }
    };
}

test "push pop sequence" {
    var buffer_space: [4]u64 = undefined;
    var buffer = RingBuffer(u64).init(&buffer_space);
    buffer.push(1);
    buffer.push(2);
    buffer.push(3);
    buffer.push(4);
    expect(buffer.pop() == 1);
    buffer.push(5);
    expect(buffer.pop() == 2);
    expect(buffer.pop() == 3);
    expect(buffer.pop() == 4);
    expect(buffer.pop() == 5);
}

test "push pop slices sequence" {
    var buffer_space: [5]u64 = undefined;
    var buffer = RingBuffer(u64).init(&buffer_space);
    buffer.push_slice(&[_]u64{ 0, 1, 2, 3 });
    buffer.next();
    var return_buffer: [3]u64 = undefined;
    buffer.pop_slice(&return_buffer);
    expect(return_buffer[0] == 1);
    expect(return_buffer[1] == 2);
    expect(return_buffer[2] == 3);
}

test "read ahead" {
    var buffer_space: [3]u64 = undefined;
    var buffer = RingBuffer(u64).init(&buffer_space);
    buffer.push(1);
    buffer.push(2);
    buffer.push(3);
    buffer.next();
    buffer.push(4);
    expect(buffer.read_ahead() == 2);
    expect(buffer.read_ahead_at(0) == 2);
    expect(buffer.read_ahead_at(1) == 3);
    expect(buffer.read_ahead_at(2) == 4);
    var read_ahead_buffer: [2]u64 = undefined;
    buffer.read_ahead_slice(&read_ahead_buffer);
    expect(read_ahead_buffer[0] == 2);
    expect(read_ahead_buffer[1] == 3);
}

test "sizes" {
    var buffer_space: [4]u64 = undefined;
    var buffer = RingBuffer(u64).init(&buffer_space);
    expect(buffer.free_size() == 4);
    expect(buffer.used_size() == 0);
    expect(buffer.is_empty());
    expect(!buffer.is_full());
    buffer.push(0);
    expect(buffer.free_size() == 3);
    expect(buffer.used_size() == 1);
    expect(!buffer.is_empty());
    expect(!buffer.is_full());
    buffer.push(1);
    buffer.push(2);
    buffer.push(3);
    expect(buffer.free_size() == 0);
    expect(buffer.used_size() == 4);
    expect(buffer.is_full());
    expect(!buffer.is_empty());
    buffer.next();
    expect(buffer.free_size() == 1);
    expect(buffer.used_size() == 3);
    expect(!buffer.is_empty());
    expect(!buffer.is_full());
}

test "skip and next" {
    var buffer_space: [4]u64 = undefined;
    var buffer = RingBuffer(u64).init(&buffer_space);
    buffer.push(0);
    buffer.push(1);
    buffer.push(2);
    buffer.push(3);
    buffer.next();
    buffer.skip(2);
    expect(buffer.pop() == 3);
}
