const std = @import("std");
const Semaphore = @import("root").os.thread.Semaphore;

// All operations can be done from interrupt context. Everything can fail.
// Not thread safe.

// https://www.snellman.net/blog/archive/2016-12-13-ring-buffers/

pub fn RingBuffer(comptime T: type, comptime max_size: usize) type {
    if(@popCount(usize, max_size) != 1) {
        // Required both for mask() and `written`/`read` overflowing
        @compileError("Size must be a power of 2!");
    }

    return struct {
        written: usize = 0,
        read: usize = 0,

        elements: [max_size]T = undefined,

        fn mask(val: usize) usize {
            return val & (max_size - 1);
        }

        pub fn size(self: @This()) usize {
            return self.written - self.read;
        }

        pub fn empty(self: @This()) bool {
            return self.size() == 0;
        }

        pub fn full(self: @This()) bool {
            return self.size() == max_size;
        }

        // Peek at the next writable slot, call send() when done writing to
        // If you don't want to write, no further action is needed
        pub fn peekWrite(self: *@This()) ?*T {
            if(self.full()) return null;
            return &self.elements[mask(self.written)];
        }

        pub fn send(self: *@This()) void {
            // Overflowing here is fine, max size is power of 2
            self.written +%= 1;
        }

        pub fn push(self: *@This(), val: T) bool {
            (self.peekWrite() orelse return false).* = val;
            self.send();
            return true;
        }

        pub fn peek(self: *@This()) ?*T {
            if(self.empty()) return null;
            return &self.elements[mask(self.read)];
        }

        pub fn drop(self: *@This()) void {
            // Overflowing here is fine, max size is power of 2
            self.read +%= 1;
        }

        pub fn pop(self: *@This()) ?T {
            const v = (self.peek() orelse return null).*;
            self.drop();
            return v;
        }
    };
}

// A RingBuffer that you can wait on and that also tracks the number of dropped elements in case the buffer is full when pushed to.
// Pushing can be done from an interrupt context, but popping cannot.
pub fn RingWaitQueue(comptime T: type, comptime max_size: usize) type {
    return struct {
        num_dropped: usize = 0,
        semaphore: Semaphore = .{.available = 1},
        buffer: RingBuffer(T, max_size) = .{},

        pub fn push(self: *@This(), val: T) bool {
            if(self.buffer.push(val)) {
                self.semaphore.release(1);
                return true;
            } else {
                _ = @atomicRmw(usize, &self.num_dropped, .Add, 1, .AcqRel);
                return false;
            }
        }

        pub fn get(self: *@This()) T {
            while(true) {
                if(self.buffer.pop()) |p| return p;
                self.semaphore.try_acquire(1);
            }
        }

        // Set the number of dropped elements to 0 and return old value
        pub fn dropped(self: *@This()) usize {
            return @atomicRmw(usize, &self.num_dropped, .Xchg, 0, .AcqRel);
        }
    };
}
