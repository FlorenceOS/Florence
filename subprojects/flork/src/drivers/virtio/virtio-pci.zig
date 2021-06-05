const std = @import("std");

/// Descriptor iterator helper.
pub const DescIter = struct {
    drv: *Driver,
    i: u8,
    curr: Descriptor,
    next: Descriptor,

    /// Put the head of a descriptor chain on the available ring
    pub fn begin(iter: *DescIter) void {
        var i = &iter.drv.queues[iter.i];
        iter.next = iter.drv.descr(iter.i);
        i.avail.rings(i.wrap(i.avail.idx +% i.pending)).* = iter.next;
        i.pending += 1;
    }
    /// Put a descriptor to be part of the descriptor chain
    pub fn put(iter: *DescIter, a: anytype, len: u32, flags: u16) void {
        iter.curr = iter.next;
        iter.next = if ((flags & VRING_DESC_F_NEXT) != 0) iter.drv.descr(iter.i) else 0xFFFF;
        assert(len <= 0x1000);
        const addr = paging.translate_virt(.{ .virt = @ptrToInt(a) }) catch |err| {
            @panic("virtio-pci: can't get the physical address");
        };
        iter.drv.queues[iter.i].desc[iter.curr] = .{ .addr = addr, .len = len, .flags = flags, .next = iter.next };
    }
};

/// The actual driver structure for the modern virtio-pci transport.
/// It expects already-initialized BARs. There is no support for the legacy PIO-only interface.
pub const Driver = struct {
    /// Find PCI BARs and initialize device
    pub fn init(a: pci.Addr, reqFeatures: u64, optFeatures: u64) !Driver {
        var drv: Driver = detectbars(a);
        drv.cfg.device_status = 0; // reset
        drv.cfg.device_status |= VIRTIO_ACKNOWLEDGE; // guest acknowledged device
        drv.cfg.device_status |= VIRTIO_DRIVER; // driver has been loaded
        errdefer drv.cfg.device_status |= VIRTIO_FAILED; // set the failed bit on unrecoverable errors

        // negotiate features
        var req = reqFeatures | (1 << VIRTIO_F_VERSION_1); // legacy devices aren't supported
        try drv.feature(0, @truncate(u32, req), @truncate(u32, optFeatures));
        try drv.feature(1, @truncate(u32, req >> 32), @truncate(u32, optFeatures >> 32));

        drv.cfg.device_status |= VIRTIO_FEATURES_OK; // features acknowledged
        if ((drv.cfg.device_status & VIRTIO_FEATURES_OK) == 0) return error.FeaturesNotAccepted;

        for (drv.queues) |_, i| drv.setupqueue(@truncate(u16, i));

        drv.cfg.device_status |= VIRTIO_DRIVER_OK; // driver initialized, start normal operation
        return drv;
    }

    /// Create descriptor iterator
    pub fn iter(drv: *Driver, i: u8) DescIter {
        return .{ .drv = drv, .i = i, .curr = 0xFFFF, .next = 0xFFFF };
    }

    /// Free the chain which starts at `head`
    pub fn freechain(drv: *Driver, i: u8, head: Descriptor) void {
        var q: *VirtQueue = &drv.queues[i];
        var last = &q.desc[head];
        while ((last.flags & VRING_DESC_F_NEXT) != 0) { // follow descriptor chain
            q.num_unused += 1;
            last = &q.desc[last.next];
        } // last is now the descriptor *after* the chain
        q.num_unused += 1;
        last.next = q.first_unused;
        last.flags = if (q.first_unused != 0xFFFF) VRING_DESC_F_NEXT else 0; // add the freed chain before the current freelist
        q.first_unused = head;
    }

    /// Process incoming events. NOTE: this does not acknowledge the interrupt, to do that, use acknowledge()
    pub fn process(drv: *Driver, i: u8, cb: anytype, ctx: anytype) void {
        var q = &drv.queues[i];
        while (q.last_in_used != q.used.idx) {
            var elem = q.used.rings(q.wrap(q.last_in_used));
            q.last_in_used = q.last_in_used +% 1;
            cb(ctx, i, @truncate(u16, elem.id));
        }
    }

    /// Make the descriptors available to the device and notify it.
    pub fn start(drv: *Driver, i: u8) void {
        // The virtio spec requires me to send values modulo 2^16, and not modulo size
        // This explains the ugly overflowing-adds
        drv.queues[i].avail.idx = drv.queues[i].avail.idx +% drv.queues[i].pending;
        drv.queues[i].pending = 0;
        drv.notify[i * drv.notify_mul] = drv.queues[i].avail.idx;
    }

    /// Acknowledge virtio interrupt
    pub fn acknowledge(drv: *Driver) void {
        var result = drv.isr.*; // Doesn't look very robust, but it works. Definitively look here if something breaks.
    }

    /// Allocate a descriptor
    pub fn descr(drv: *Driver, i: u8) Descriptor {
        var q = &drv.queues[i];
        var first_un = q.first_unused;
        if ((first_un == 0xFFFF) or (q.num_unused == 0)) @panic("virtio-pci: not enough descriptors");
        q.first_unused = q.desc[first_un].next;
        drv.queues[i].num_unused -= 1;
        return first_un;
    }

    /// Negotiate feature bitmask with device, ZIG BUG, bad codegen without .Inline, no issue open
    fn feature(drv: *Driver, i: u32, req: u32, opt: u32) callconv(if (@hasField(std.builtin.CallingConvention, "Inline")) .Inline else .Unspecified) !void {
        drv.cfg.device_feature_select = i;
        const f = drv.cfg.device_feature & (req | opt);
        if ((f & req) != req) return error.FeatureNotAvailable;
        drv.cfg.guest_feature_select = i;
        drv.cfg.guest_feature = f;
    }

    /// Detect BARs and capabilities and set up the cfg/notify/isr/dev structures
    fn detectbars(a: pci.Addr) Driver {
        var drv: Driver = undefined;
        var cap = a.cap();
        while (cap.off != 0) {
            const vndr = cap.vndr();
            if (vndr == 0x09) {
                const cfg_typ = cap.read(u8, VIRTIO_PCI_CAP_CFG_TYPE);
                const bar = cap.read(u8, VIRTIO_PCI_CAP_BAR);
                const off = cap.read(u32, VIRTIO_PCI_CAP_OFFSET);
                const len = cap.read(u32, VIRTIO_PCI_CAP_LENGTH);

                const phy = a.barinfo(bar).phy + off;
                switch (cfg_typ) {
                    VIRTIO_PCI_CAP_COMMON_CFG => {
                        drv.cfg = os.platform.phys_ptr(*volatile CommonCfg).from_int(phy).get_uncached();
                    },
                    VIRTIO_PCI_CAP_NOTIFY_CFG => {
                        drv.notify_mul = cap.read(u32, VIRTIO_PCI_NOTIFY_CAP_MULT) / 2; // VIRTIO_PCI_NOTIFY_CAP_MULT is a byte offset, each field is u16
                        drv.notify = os.platform.phys_ptr([*]volatile u16).from_int(phy).get_uncached();
                    },
                    VIRTIO_PCI_CAP_ISR_CFG => {
                        drv.isr = os.platform.phys_ptr(*volatile u32).from_int(phy).get_uncached();
                    },
                    VIRTIO_PCI_CAP_DEVICE_CFG => {
                        drv.dev = os.platform.phys_ptr([*]volatile u8).from_int(phy).get_uncached();
                    },
                    VIRTIO_PCI_CAP_PCI_CFG => {},
                    else => {}, // ignore
                }
            }
            cap.next();
        }
        return drv;
    }

    /// Set up a specific queue
    fn setupqueue(drv: *Driver, i: u16) void {
        drv.cfg.queue_select = i;
        const size = drv.cfg.queue_size;
        if (size == 0) return;
        const desc_siz: u32 = @sizeOf(VirtqDesc) * size;
        const avail_siz: u32 = @sizeOf(VirtqAvail) + 2 + 2 * size;
        const used_siz: u32 = @sizeOf(VirtqUsed) + 2 + @sizeOf(VirtqUsedItem) * size;
        const total_siz = desc_siz + avail_siz + used_siz;
        const phys = os.memory.pmm.alloc_phys(size) catch unreachable;
        const virt = os.platform.phys_ptr([*]volatile u8).from_int(phys).get_uncached();
        @memset(virt, 0x00, total_siz);

        drv.queues[i] = .{
            .desc = @ptrCast([*]VirtqDesc, virt),
            .avail = @ptrCast(*VirtqAvail, virt + desc_siz),
            .used = @ptrCast(*VirtqUsed, virt + desc_siz + avail_siz),
            .size = size,
            .num_unused = size,
            .first_unused = 0,
            .last_in_used = 0,
            .pending = 0,
        };

        var m: u16 = 0;
        while (m < size - 1) : (m += 1) {
            drv.queues[i].desc[m] = .{ .flags = VRING_DESC_F_NEXT, .next = m + 1, .addr = 0, .len = 0 };
        }
        drv.queues[i].desc[m].next = 0xFFFF;

        drv.cfg.queue_desc = phys;
        drv.cfg.queue_avail = phys + desc_siz;
        drv.cfg.queue_used = phys + desc_siz + avail_siz;
        drv.cfg.queue_enable = 1; // important: this enables the queue
    }

    cfg: *volatile CommonCfg,
    notify: [*]volatile Descriptor,
    notify_mul: u32,
    isr: *volatile u32,
    dev: [*]volatile u8,
    queues: [16]VirtQueue = undefined,
};

pub const Descriptor = u16; // descriptor id

const os = @import("root").os;
const lib = @import("root");
const libalign = lib.libalign;
const allocator = os.memory.vmm.backed(.Ephemeral);
const pmm = os.memory.pmm;
const paging = os.memory.paging;
const pci = os.platform.pci;
const assert = @import("std").debug.assert;

/// Ring descriptor, actual structure (`Descriptor` is only its id)
const VirtqDesc = packed struct {
    addr: u64, // guest phyaddr
    len: u32,
    flags: u16,
    next: Descriptor,
};
// ring flags
pub const VRING_DESC_F_NEXT: u32 = 1;
pub const VRING_DESC_F_WRITE: u32 = 2;
pub const VRING_DESC_F_INDIRECT: u32 = 4;

const VirtqAvail = packed struct {
    flags: u16,
    idx: Descriptor, // important: virtio requires this field to have the index without wraparound
    pub fn rings(self: *volatile VirtqAvail, desc: Descriptor) *volatile u16 {
        return @intToPtr(*volatile u16, @ptrToInt(self) + @sizeOf(VirtqAvail) + desc * 2);
    }
};

const VirtqUsedItem = packed struct {
    id: u32, // descriptor chain head
    len: u32,
};

const VirtqUsed = packed struct {
    flags: u16,
    idx: u16, // last used idx, the driver keeps the first in last_in_used
    pub fn rings(self: *volatile VirtqUsed, desc: Descriptor) *volatile VirtqUsedItem {
        return @intToPtr(*volatile VirtqUsedItem, @ptrToInt(self) + @sizeOf(VirtqUsed) + desc * @sizeOf(VirtqUsedItem));
    }
};

const VirtQueue = struct {
    desc: [*]volatile VirtqDesc,
    avail: *volatile VirtqAvail,
    used: *volatile VirtqUsed,

    size: u16,
    first_unused: Descriptor,
    last_in_used: u16, // index into used.rings()
    num_unused: u16,
    pending: u16,

    // the size of a queue is guaranteed to be a power of two, so it's possible to save on a modulo
    // and instead get the mask to AND
    pub fn wrap(self: *@This(), val: u16) u16 {
        return val & (self.size - 1);
    }
};

const CommonCfg = packed struct {
    device_feature_select: u32,
    device_feature: u32,
    guest_feature_select: u32,
    guest_feature: u32,
    msix_config: u16,
    num_queues: u16,
    device_status: u8,
    config_generation: u8,

    queue_select: u16,
    queue_size: u16,
    queue_msix_vector: u16,
    queue_enable: u16,
    queue_notify_off: u16,
    queue_desc: u64,
    queue_avail: u64,
    queue_used: u64,
};

const VIRTIO_ACKNOWLEDGE: u8 = 1;
const VIRTIO_DRIVER: u8 = 2;
const VIRTIO_FAILED: u8 = 128;
const VIRTIO_FEATURES_OK: u8 = 8;
const VIRTIO_DRIVER_OK: u8 = 4;
const VIRTIO_DEVICE_NEEDS_RESET: u8 = 64;

// Capability config types
const VIRTIO_PCI_CAP_COMMON_CFG = 1;
const VIRTIO_PCI_CAP_NOTIFY_CFG = 2;
const VIRTIO_PCI_CAP_ISR_CFG = 3;
const VIRTIO_PCI_CAP_DEVICE_CFG = 4;
const VIRTIO_PCI_CAP_PCI_CFG = 5;

// PCI capability list record offsets
const VIRTIO_PCI_CAP_LEN = 2;
const VIRTIO_PCI_CAP_CFG_TYPE = 3;
const VIRTIO_PCI_CAP_BAR = 4;
const VIRTIO_PCI_CAP_OFFSET = 8;
const VIRTIO_PCI_CAP_LENGTH = 12;
const VIRTIO_PCI_NOTIFY_CAP_MULT = 16;

// Feature bits
const VIRTIO_F_VERSION_1 = 32;
const VIRTIO_F_ACCESS_PLATFORM = 33;
const VIRTIO_F_RING_PACKED = 34;
const VIRTIO_F_ORDER_PLATFORM = 36;
const VIRTIO_F_SR_IOV = 37;
