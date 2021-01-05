const std = @import("std");
const os = @import("root").os;

const cpu_id = u32;
var inited = false;

const cpu_data = struct {
  current_task: ?*os.thread.Task = null,
  numa: *numa_data,
  booted: bool = false,
};

var cpus: []cpu_data = &[0]cpu_data{};

const numa_data = struct {

};

pub fn init() void {
  if(inited)
    return;
  inited = true;

  cpu_map.init();
}

pub fn set_booted(id: cpu_id) void {

}

pub fn is_booted(id: cpu_id) bool {

}
