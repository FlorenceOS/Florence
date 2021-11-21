const std = @import("std");

const ImageRegion = @import("image_region").ImageRegion;
const Color = @import("color").Color;

pub const ScrollingRegion = struct {
    used_height: usize = 0,
    used_width: usize = 0,

    pub fn putBottom(self: *@This(), region: ImageRegion, into: ImageRegion, used_width: usize) void {
        if (region.width != into.width) unreachable;

        if (self.used_height + region.height > into.height) {
            // We need to scroll
            const to_scroll = self.used_height + region.height - into.height;

            // Do the scroll without invalidating
            into.drawImage(into.subregion(0, to_scroll, self.used_width, into.height - to_scroll), 0, 0, false);
            self.used_height -= to_scroll;

            self.used_width = std.math.max(self.used_width, used_width);

            // Draw the next line without invalidating
            into.drawImage(region.subregion(0, 0, self.used_width, region.height), 0, self.used_height, false);

            // Invalidate entire region
            into.invalidateRect(0, 0, self.used_width, into.height);
        } else {
            // Just add the line and invalidate it
            into.drawImage(region.subregion(0, 0, used_width, region.height), 0, self.used_height, true);

            self.used_width = std.math.max(self.used_width, used_width);
        }

        self.used_height += region.height;
    }

    pub fn retarget(self: *@This(), old: ImageRegion, new: ImageRegion, bg: Color) void {
        // Switching targets, calculate max copy size
        const copy_width = std.math.min(new.width, std.math.min(old.width, self.used_width));
        const copy_height = std.math.min(new.height, old.height);

        // Clear the rest of the new region
        if (copy_width < new.width)
            new.fill(bg, copy_width, 0, new.width - copy_width, new.height, false);

        if (copy_height >= self.used_height) {
            // We're not using the entire height, just copy it over and leave current used height as is
            new.drawImage(old.subregion(0, 0, copy_width, copy_height), 0, 0, false);

            // Pad at bottom if needed
            if (copy_height < new.height)
                new.fill(bg, 0, copy_height, copy_width, new.height - copy_height, false);
        } else {
            // We want to copy the `copy_height` last pixel lines
            const old_copy_y_offset = old.height - copy_height;
            const new_copy_y_offset = new.height - copy_height;

            new.drawImage(old.subregion(0, old_copy_y_offset, copy_width, copy_height), 0, new_copy_y_offset, false);

            // Entire framebuffer is in use
            self.used_height = new.height;
        }

        // Pad at side if needed
        if (copy_width < new.width)
            new.fill(bg, copy_width, 0, new.width - copy_width, new.height, false);

        self.used_width = copy_width;

        // Invalidate entire new target, we've drawn to all of it
        new.invalidateRect(0, 0, new.width, new.height);
    }
};
