usingnamespace @import("root").preamble;

const virtio_pci = os.drivers.misc.virtio_pci;

/// virtio-gpu driver instance
const Driver = struct {
    transport: virtio_pci.Driver,
    inflight: u32 = 0,
    pitch: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,

    // Initialize the virtio transport, but don't change modes
    pub fn init(pciaddr: os.platform.pci.Addr) !Driver {
        var v = try virtio_pci.Driver.init(pciaddr, 0, 0);
        var d: Driver = .{ .transport = v };
        return d;
    }

    // Do a modeswitch to the described mode
    pub fn modeset(self: *Driver, addr: u64, width: u32, height: u32) void {
        self.pitch = width * 4;
        self.width = width;
        self.height = height;
        var iter = self.transport.iter(0);
        {
            var msg: ResourceCreate2D = .{
                .hdr = .{
                    .cmdtype = virtio_gpu_cmd_res_create_2d,
                    .flags = 0,
                    .fenceid = 0,
                    .ctxid = 0,
                },
                .resid = 1,
                .format = 1,
                .width = width,
                .height = height,
            };
            var resp: ConfHdr = undefined;
            iter.begin();
            iter.put(&msg, @sizeOf(ResourceCreate2D), virtio_pci.vring_desc_flag_next);
            iter.put(&resp, @sizeOf(ConfHdr), virtio_pci.vring_desc_flag_write);
            self.inflight += 1;
        }

        {
            var msg: ResourceAttachBacking = .{
                .hdr = .{
                    .cmdtype = virtio_gpu_cmd_res_attach_backing,
                    .flags = 0,
                    .fenceid = 0,
                    .ctxid = 0,
                },
                .resid = 1,
                .entrynum = 1,
            };
            var msg1: ResourceAttachBackingEntry = .{ .addr = addr, .len = width * height * 4 };
            var resp: ConfHdr = undefined;
            iter.begin();
            iter.put(&msg, @sizeOf(ResourceAttachBacking), virtio_pci.vring_desc_flag_next);
            iter.put(&msg1, @sizeOf(ResourceAttachBackingEntry), virtio_pci.vring_desc_flag_next);
            iter.put(&resp, @sizeOf(ConfHdr), virtio_pci.vring_desc_flag_write);
            self.inflight += 1;
        }

        {
            var msg: SetScanout = .{
                .hdr = .{
                    .cmdtype = virtio_gpu_cmd_set_scanout,
                    .flags = 0,
                    .fenceid = 0,
                    .ctxid = 0,
                },
                .resid = 1,
                .scanid = 0,
                .rect = .{ .x = 0, .y = 0, .width = width, .height = height },
            };
            var resp: ConfHdr = undefined;
            iter.begin();
            iter.put(&msg, @sizeOf(SetScanout), virtio_pci.vring_desc_flag_next);
            iter.put(&resp, @sizeOf(ConfHdr), virtio_pci.vring_desc_flag_write);
            self.inflight += 1;
        }

        self.transport.start(0);
        self.wait();

        self.updateRect(0, .{ .x = 0, .y = 0, .width = width, .height = height });
    }

    /// Update *only* the rectangle
    pub fn updateRect(self: *Driver, offset: u64, rect: Rect) void {
        var iter = self.transport.iter(0);
        {
            var msg: TransferHost2D = .{
                .hdr = .{
                    .cmdtype = virtio_gpu_cmd_transfer_to_host_2d,
                    .flags = 0,
                    .fenceid = 0,
                    .ctxid = 0,
                },
                .resid = 1,
                .offset = offset,
                .rect = rect,
            };
            var resp: ConfHdr = undefined;
            iter.begin();
            iter.put(&msg, @sizeOf(TransferHost2D), virtio_pci.vring_desc_flag_next);
            iter.put(&resp, @sizeOf(ConfHdr), virtio_pci.vring_desc_flag_write);
            self.inflight += 1;
        }
        {
            var msg: ResourceFlush = .{
                .hdr = .{
                    .cmdtype = virtio_gpu_cmd_res_flush,
                    .flags = 0,
                    .fenceid = 0,
                    .ctxid = 0,
                },
                .resid = 1,
                .rect = rect,
            };
            var resp: ConfHdr = undefined;
            iter.begin();
            iter.put(&msg, @sizeOf(ResourceFlush), virtio_pci.vring_desc_flag_next);
            iter.put(&resp, @sizeOf(ConfHdr), virtio_pci.vring_desc_flag_write);
            self.inflight += 1;
        }
        self.transport.start(0);

        self.wait();
    }

    /// Wait for request to finish.
    fn wait(self: *Driver) void {
        while (true) {
            var a: *volatile u32 = &self.inflight;
            if (a.* == 0) break;
            self.transport.process(0, process, self);
        }
    }
};

const ConfHdr = packed struct {
    cmdtype: u32,
    flags: u32,
    fenceid: u64,
    ctxid: u32,
    _: u32 = 0,
};

const ResourceCreate2D = packed struct {
    hdr: ConfHdr, resid: u32, format: u32, width: u32, height: u32
};

const ResourceAttachBacking = packed struct {
    hdr: ConfHdr, resid: u32, entrynum: u32
};

const ResourceAttachBackingEntry = packed struct {
    addr: u64,
    len: u32,
    _: u32 = 0,
};

const Rect = packed struct {
    x: u32, y: u32, width: u32, height: u32
};

const SetScanout = packed struct {
    hdr: ConfHdr,
    rect: Rect,
    scanid: u32,
    resid: u32,
};

const TransferHost2D = packed struct {
    hdr: ConfHdr, rect: Rect, offset: u64, resid: u32, _: u32 = 0
};

const ResourceFlush = packed struct {
    hdr: ConfHdr, rect: Rect, resid: u32, _: u32 = 0
};

// Feature bits
const virtio_feature_version_1 = 32;
const virtio_feature_access_platform = 33;
const virtio_feature_ring_packed = 34;
const virtio_feature_order_platform = 36;
const virtio_feature_sr_iov = 37;

// 2D cmds
const virtio_gpu_cmd_get_display_info = 0x0100;
const virtio_gpu_cmd_res_create_2d = 0x101;
const virtio_gpu_cmd_res_unref = 0x102;
const virtio_gpu_cmd_set_scanout = 0x103;
const virtio_gpu_cmd_res_flush = 0x104;
const virtio_gpu_cmd_transfer_to_host_2d = 0x105;
const virtio_gpu_cmd_res_attach_backing = 0x106;
const virtio_gpu_cmd_res_detatch_backing = 0x107;
const virtio_gpu_cmd_get_capset_info = 0x108;
const virtio_gpu_cmd_get_capset = 0x109;
const virtio_gpu_cmd_get_edid = 0x10A;

// Cursor cmds
const virtio_gpu_cmd_update_cursor = 0x0300;
const virtio_gpu_cmd_move_cursor = 0x301;

// Success
const virtio_gpu_resp_ok_nodata = 0x1100;
const virtio_gpu_resp_ok_display_info = 0x1101;
const virtio_gpu_resp_ok_capset_info = 0x1102;
const virtio_gpu_resp_ok_capset = 0x1103;
const virtio_gpu_resp_ok_edid = 0x1104;

// Error
const virtio_gpu_resp_err_unspecified = 0x1200;
const virtio_gpu_resp_err_out_of_mem = 0x1201;
const virtio_gpu_resp_err_invalid_scanout_id = 0x1202;
const virtio_gpu_resp_err_invalid_res_id = 0x1203;
const virtio_gpu_resp_err_invalid_ctx_id = 0x1204;
const virtio_gpu_resp_err_invalid_parameter = 0x1205;

const virtio_gpu_flag_fence = (1 << 0);

fn process(self: *Driver, i: u8, head: virtio_pci.Descriptor) void {
    self.transport.freeChain(i, head);
    self.inflight -= 1;
}

/// Global rectangle update, but with a global context
fn updater(
    bb: [*]u8,
    yoff_src: usize,
    yoff_dest: usize,
    ysize: usize,
    pitch: usize,
    ctx: usize,
) void {
    var self = @intToPtr(*Driver, ctx);
    self.updateRect(self.pitch * yoff_src, .{
        .x = 0,
        .y = @truncate(u32, yoff_dest),
        .width = self.width,
        .height = @truncate(u32, ysize),
    });
}

pub fn registerController(addr: os.platform.pci.Addr) void {
    const alloc = os.memory.vmm.backed(.Eternal);
    const drv = alloc.create(Driver) catch {
        os.log("Virtio display controller: Allocation failure\n", .{});
        return;
    };
    drv.* = Driver.init(addr) catch {
        os.log("Virtio display controller: Init has failed!\n", .{});
        return;
    };
    if (os.drivers.output.vesa_log.getInfo()) |vesa| {
        drv.modeset(os.drivers.output.vesa_log.framebuffer.?.bb_phys, vesa.width, vesa.height);
        os.drivers.output.vesa_log.setUpdater(updater, @ptrToInt(drv));
        os.log("Virtio display controller: Initialized with preexisting fb\n", .{});
    } else {
        os.drivers.output.vesa_log.registerFb(updater, @ptrToInt(drv), 800 * 4, 800, 600, 32);
        drv.modeset(os.drivers.output.vesa_log.getBackbufferPhys(), 800, 600);
        os.log("Virtio display controller: Initialized\n", .{});
    }
}

/// General callback on an interrupt, context is a pointer to a Driver structure
pub fn interrupt(frame: *os.platform.InterruptFrame, context: u64) void {
    var driver = @intToPtr(*Driver, context);
    driver.transport.acknowledge();
    driver.transport.process(0, process, driver);
}
