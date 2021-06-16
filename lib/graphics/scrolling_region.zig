usingnamespace @import("root").preamble;

const ImageRegion = lib.graphics.image_region.ImageRegion;
const Color = lib.graphics.color.Color;

pub const ScrollingRegion = struct {
    used_height: usize = 0,

    pub fn putBottom(self: *@This(), region: ImageRegion, into: ImageRegion) void {
        if (region.width != into.width) unreachable;

        if (self.used_height + region.height > into.height) {
            // We need to scroll
            const to_scroll = self.used_height + region.height - into.height;

            // Do the scroll without invalidating
            into.drawImage(into.subregion(0, to_scroll, into.width, into.height - to_scroll), 0, 0, false);
            self.used_height -= to_scroll;

            // Draw the next line without invalidating
            into.drawImage(region, 0, self.used_height, false);

            // Invalidate entire region
            into.invalidateRect(0, 0, into.width, into.height);
        } else {
            // Just add the line and invalidate it
            into.drawImage(region, 0, self.used_height, true);
        }

        self.used_height += region.height;
    }

    pub fn retarget(self: *@This(), old: ImageRegion, new: ImageRegion, bg: Color) void {
        // Switching targets, calculate max copy size
        const copy_width = std.math.min(new.width, old.width);
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

        // Invalidate entire new target, we've drawn to all of it
        new.invalidateRect(0, 0, new.width, new.height);
    }
};
