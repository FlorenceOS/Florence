const os = @import("root").os;
const atmcqueue = os.lib.atmcqueue;

pub const Task = struct {
  registers: os.platform.InterruptFrame = undefined,
  allocated_core_id: usize = undefined,
  platform_data: os.platform.TaskData = undefined,
  atmcqueue_hook: atmcqueue.Node = undefined,
};
