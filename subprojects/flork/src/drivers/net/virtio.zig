usingnamespace @import("root").preamble;

const log = lib.output.log.scoped(.{
    .prefix = "VirtioNet",
    .filter = .info,
}).write;

const virtio_pci = os.drivers.misc.virtio_pci;

const DevConfig = packed struct {
    mac: [6]u8,
};

/// virtio-net driver instance
const Driver = struct {
    transport: virtio_pci.Driver,
    mac: [6]u8 = undefined,
    inflight: u32 = 0,

    // Initialize the virtio transport, but don't change modes
    pub fn init(pciaddr: os.platform.pci.Addr) !Driver {
        var v = try virtio_pci.Driver.init(pciaddr, VIRTIO_NET_F_MAC, 0);
        var d: Driver = .{ .transport = v };
        const c = @ptrCast(*volatile DevConfig, d.transport.dev);
        log(.info, "MAC addr {0X}:{0X}:{0X}:{0X}:{0X}:{0X}", .{ c.mac[0], c.mac[1], c.mac[2], c.mac[3], c.mac[4], c.mac[5] });

        var iter = d.transport.iter(1);
        {
            var hdr: NetHdr = .{};
            iter.begin();
            iter.put(&hdr, @sizeOf(NetHdr), virtio_pci.vring_desc_flag_next);
            const text = "testing";
            iter.put(&text[0], text.len, 0);
            d.inflight = 1;
        }
        d.transport.start(1);

        d.wait(1);

        return d;
    }

    /// Wait for request to finish.
    fn wait(self: *Driver, queue: u8) void {
        while (true) {
            var a: *volatile u32 = &self.inflight;
            if (a.* == 0) break;
            self.transport.process(queue, process, self);
        }
    }
};

fn process(self: *Driver, i: u8, head: virtio_pci.Descriptor) void {
    self.transport.freeChain(i, head);
    self.inflight -= 1;
}

pub fn registerController(addr: os.platform.pci.Addr) void {
    const alloc = os.memory.pmm.phys_heap;
    const drv = alloc.create(Driver) catch {
        log(.crit, "Virtio Ethernet controller: Allocation failure", .{});
        return;
    };
    errdefer alloc.destroy(drv);
    drv.* = Driver.init(addr) catch {
        log(.crit, "Virtio Ethernet controller: Init has failed!", .{});
        return;
    };
    errdefer drv.deinit();
}

pub fn interrupt(drv: *Driver) void {
}

const VIRTIO_NET_F_MAC = 1 << 5;

const NetHdr = packed struct {
    flags: u8 = 0,
    gso_type: u8 = 0,
    hdr_len: u16 = 0,
    gso_size: u16 = 0,
    csum_start: u16 = 0,
    csum_offset: u16 = 0,
    num_buffers: u16 = 0,
};
