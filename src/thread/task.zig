const os = @import("root").os;

pub const Task = struct {
  registers: os.platform.InterruptFrame = undefined,
  platform_data: os.platform.TaskData = undefined,
  next_task: ?*@This() = undefined,
};
