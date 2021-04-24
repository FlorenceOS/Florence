/// virtio-gpu driver instance
const Driver = struct {
  transport: virtio.Driver,
  inflight: u32 = 0,
  pitch: u32 = 0,
  width: u32 = 0,
  height: u32 = 0,

  // Initialize the virtio transport, but don't change modes
  pub fn init(pciaddr: pci.Addr) !Driver {
    var v = try virtio.Driver.init(pciaddr, 0, 0);
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
        .hdr = .{ .cmdtype = VIRTIO_GPU_CMD_RESOURCE_CREATE_2D, .flags = 0, .fenceid = 0, .ctxid = 0 },
        .resid = 1,
        .format = 1,
        .width = width,
        .height = height,
      };
      var resp: ConfHdr = undefined;
      iter.begin();
      iter.put(&msg, @sizeOf(ResourceCreate2D), virtio.VRING_DESC_F_NEXT);
      iter.put(&resp, @sizeOf(ConfHdr), virtio.VRING_DESC_F_WRITE);
      self.inflight += 1;
    }

    {
      var msg: ResourceAttachBacking = .{
        .hdr = .{ .cmdtype = VIRTIO_GPU_CMD_RESOURCE_ATTACH_BACKING, .flags = 0, .fenceid = 0, .ctxid = 0 },
        .resid = 1,
        .entrynum = 1,
      };
      var msg1: ResourceAttachBackingEntry = .{ .addr = addr, .len = width * height * 4 };
      var resp: ConfHdr = undefined;
      iter.begin();
      iter.put(&msg, @sizeOf(ResourceAttachBacking), virtio.VRING_DESC_F_NEXT);
      iter.put(&msg1, @sizeOf(ResourceAttachBackingEntry), virtio.VRING_DESC_F_NEXT);
      iter.put(&resp, @sizeOf(ConfHdr), virtio.VRING_DESC_F_WRITE);
      self.inflight += 1;
    }

    {
      var msg: SetScanout = .{
        .hdr = .{ .cmdtype = VIRTIO_GPU_CMD_SET_SCANOUT, .flags = 0, .fenceid = 0, .ctxid = 0 },
        .resid = 1,
        .scanid = 0,
        .rect = .{ .x = 0, .y = 0, .width = width, .height = height },
      };
      var resp: ConfHdr = undefined;
      iter.begin();
      iter.put(&msg, @sizeOf(SetScanout), virtio.VRING_DESC_F_NEXT);
      iter.put(&resp, @sizeOf(ConfHdr), virtio.VRING_DESC_F_WRITE);
      self.inflight += 1;
    }

    self.transport.start(0);
    self.wait();

    self.update_rect(0, .{.x = 0, .y = 0, .width = width, .height = height});
  }

  /// Update *only* the rectangle
  pub fn update_rect(self: *Driver, offset: u64, rect: Rect) void {

    var iter = self.transport.iter(0);
    {
      var msg: TransferHost2D = .{
        .hdr = .{ .cmdtype = VIRTIO_GPU_CMD_TRANSFER_TO_HOST_2D, .flags = 0, .fenceid = 0, .ctxid = 0 },
        .resid = 1,
        .offset = offset,
        .rect = rect,
      };
      var resp: ConfHdr = undefined;
      iter.begin();
      iter.put(&msg, @sizeOf(TransferHost2D), virtio.VRING_DESC_F_NEXT);
      iter.put(&resp, @sizeOf(ConfHdr), virtio.VRING_DESC_F_WRITE);
      self.inflight += 1;
    }
    {
      var msg: ResourceFlush = .{
        .hdr = .{ .cmdtype = VIRTIO_GPU_CMD_RESOURCE_FLUSH, .flags = 0, .fenceid = 0, .ctxid = 0 },
        .resid = 1,
        .rect = rect,
      };
      var resp: ConfHdr = undefined;
      iter.begin();
      iter.put(&msg, @sizeOf(ResourceFlush), virtio.VRING_DESC_F_NEXT);
      iter.put(&resp, @sizeOf(ConfHdr), virtio.VRING_DESC_F_WRITE);
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

pub fn handle_controller(addr: pci.Addr) void {
  const alloc = os.memory.vmm.backed(.Eternal);
  const drv = alloc.create(Driver) catch {
    os.log("Virtio display controller: Allocation failure\n", .{});
    return;
  };
  drv.* = Driver.init(addr) catch {
    os.log("Virtio display controller: Init has failed!\n", .{});
    return;
  };
  if (os.drivers.vesa_log.get_info()) |vesa| {
    drv.modeset(os.drivers.vesa_log.framebuffer.?.bb_phys, vesa.width, vesa.height);
    os.drivers.vesa_log.set_updater(updater, @ptrToInt(drv));
    os.log("Virtio display controller: Initialized with preexisting fb\n", .{});
  } else {
    os.drivers.vesa_log.register_fb(updater, @ptrToInt(drv), 800*4, 800, 600, 32);
    drv.modeset(os.drivers.vesa_log.get_backbuffer_phy(), 800, 600);
    os.log("Virtio display controller: Initialized\n", .{});
  }
}

fn process(self: *Driver, i: u8, head: virtio.Descriptor) void {
  self.transport.freechain(i, head);
  self.inflight -= 1;
}

/// General callback on an interrupt, context is a pointer to a Driver structure
pub fn interrupt(frame: *os.platform.InterruptFrame, context: u64) void {
  var driver = @intToPtr(*Driver, context);
  driver.transport.acknowledge();
  driver.transport.process(0, process, driver);
}

/// Global rectangle update, but with a global context
fn updater(bb: [*]u8, yoff_src: usize, yoff_dest: usize, ysize: usize, pitch: usize, ctx: usize) void {
  var self = @intToPtr(*Driver, ctx);
  self.update_rect(self.pitch * yoff_src, .{ .x = 0, .y = @truncate(u32, yoff_dest), .width = self.width, .height = @truncate(u32, ysize) });
}

const virtio = @import("virtio-pci.zig");
const os = @import("root").os;
const paging = os.memory.paging;
const pmm = os.memory.pmm;
const pci = os.platform.pci;

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
const VIRTIO_F_VERSION_1 = 32;
const VIRTIO_F_ACCESS_PLATFORM = 33;
const VIRTIO_F_RING_PACKED = 34;
const VIRTIO_F_ORDER_PLATFORM = 36;
const VIRTIO_F_SR_IOV = 37;

// 2D cmds
const VIRTIO_GPU_CMD_GET_DISPLAY_INFO = 0x0100;
const VIRTIO_GPU_CMD_RESOURCE_CREATE_2D = 0x101;
const VIRTIO_GPU_CMD_RESOURCE_UNREF = 0x102;
const VIRTIO_GPU_CMD_SET_SCANOUT = 0x103;
const VIRTIO_GPU_CMD_RESOURCE_FLUSH = 0x104;
const VIRTIO_GPU_CMD_TRANSFER_TO_HOST_2D = 0x105;
const VIRTIO_GPU_CMD_RESOURCE_ATTACH_BACKING = 0x106;
const VIRTIO_GPU_CMD_RESOURCE_DETACH_BACKING = 0x107;
const VIRTIO_GPU_CMD_GET_CAPSET_INFO = 0x108;
const VIRTIO_GPU_CMD_GET_CAPSET = 0x109;
const VIRTIO_GPU_CMD_GET_EDID = 0x10A;

// Cursor cmds
const VIRTIO_GPU_CMD_UPDATE_CURSOR = 0x0300;
const VIRTIO_GPU_CMD_MOVE_CURSOR = 0x301;

// Success
const VIRTIO_GPU_RESP_OK_NODATA = 0x1100;
const VIRTIO_GPU_RESP_OK_DISPLAY_INFO = 0x1101;
const VIRTIO_GPU_RESP_OK_CAPSET_INFO = 0x1102;
const VIRTIO_GPU_RESP_OK_CAPSET = 0x1103;
const VIRTIO_GPU_RESP_OK_EDID = 0x1104;

// Error
const VIRTIO_GPU_RESP_ERR_UNSPEC = 0x1200;
const VIRTIO_GPU_RESP_ERR_OUT_OF_MEMORY = 0x1201;
const VIRTIO_GPU_RESP_ERR_INVALID_SCANOUT_ID = 0x1202;
const VIRTIO_GPU_RESP_ERR_INVALID_RESOURCE_ID = 0x1203;
const VIRTIO_GPU_RESP_ERR_INVALID_CONTEXT_ID = 0x1204;
const VIRTIO_GPU_RESP_ERR_INVALID_PARAMETER = 0x1205;

const VIRTIO_GPU_FLAG_FENCE = (1 << 0);
