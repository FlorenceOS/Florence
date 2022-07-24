// A switcher maintains two "views" which can be switched between programatically
const single_buffer = @import("single_buffer.zig");
const image_region = @import("image_region.zig");

const std = @import("std");

pub fn BufferSwitcher(comptime Mutex: type) type {
    return struct {
        target: *image_region.ImageRegion,

        // Stops us from swapping while drawing or invalidation is going on
        currently_drawing_lock: Mutex = .{},
        primary_active: bool = true,
        primary: single_buffer.BufferWithInvalidateHook(invalidatePrimary),
        secondary: single_buffer.BufferWithInvalidateHook(invalidateSecondary),

        pub fn init(
            target: *image_region.ImageRegion,
            allocator: std.mem.Allocator,
        ) !@This() {
            return @This() {
                .target = target,
                .primary = try single_buffer.BufferWithInvalidateHook(invalidatePrimary).initMatching(allocator, target.*),
                .secondary = try single_buffer.BufferWithInvalidateHook(invalidateSecondary).initMatching(allocator, target.*),
            };
        }

        pub fn retarget(
            self: *@This(),
            target: *image_region.ImageRegion,
            allocator: std.mem.Allocator,
        ) !void {
            // TODO: Tell consumers to retarget to new buffers

            self.secondary.deinit(allocator);
            self.primary.deinit(allocator);

            self.* = try init(target, allocator);
        }

        pub fn showPrimary(self: *@This()) void {
            self.currently_drawing_lock.lock();
            defer self.currently_drawing_lock.unlock();

            if(self.primary_active) return;
            self.primary_active = true;

            self.target.drawImageSameFmt(self.primary.region().*, 0, 0, true);
        }

        pub fn showSecondary(self: *@This()) void {
            self.currently_drawing_lock.lock();
            defer self.currently_drawing_lock.unlock();

            if(!self.primary_active) return;
            self.primary_active = false;

            self.target.drawImageSameFmt(self.secondary.region().*, 0, 0, true);
        }

        pub fn swap(self: *@This()) void {
            if(self.primary_active) {
                self.showSecondary();
            } else {
                self.showPrimary();
            }
        }

        fn invalidatePrimary(r: *image_region.ImageRegion, hooked_buf: anytype, x: usize, y: usize, width: usize, height: usize) void {
            const self = @fieldParentPtr(@This(), "primary", hooked_buf);

            if(!self.primary_active)
                return;

            self.currently_drawing_lock.lock();
            defer self.currently_drawing_lock.unlock();

            self.target.drawImageSameFmt(r.subregion(x, y, width, height), x, y, true);
        }

        fn invalidateSecondary(r: *image_region.ImageRegion, hooked_buf: anytype, x: usize, y: usize, width: usize, height: usize) void {
            const self = @fieldParentPtr(@This(), "secondary", hooked_buf);

            if(self.primary_active)
                return;

            self.currently_drawing_lock.lock();
            defer self.currently_drawing_lock.unlock();

            self.target.drawImageSameFmt(r.subregion(x, y, width, height), x, y, true);
        }
    };
}
