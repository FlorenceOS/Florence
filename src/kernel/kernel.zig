const os = @import("root").os;
const arch = @import("builtin").arch;

fn task_func(name: []const u8) !void {
  var i: usize = 0;
  while(true) : (i += 1) {
    os.log("Hello from task {s}, iteration {}\n", .{name, i});
    os.thread.scheduler.yield();
  }
}

pub fn kmain() noreturn {
  os.log("Hello, kmain!\n", .{});

  os.vital(os.thread.scheduler.spawn_task(task_func, .{"foo"}), "foo");
  os.vital(os.thread.scheduler.spawn_task(task_func, .{"bar"}), "bar");
  os.vital(os.thread.scheduler.spawn_task(task_func, .{"baz"}), "baz");

  // var i: usize = 0;
  // while(true) : (i += 1) {
  //   //os.log("Woop {}\n", .{i});
  // }

  while(true) {
    os.thread.scheduler.yield();
  }
  //os.thread.scheduler.exit_task();
}
