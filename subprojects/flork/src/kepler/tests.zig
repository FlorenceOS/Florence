const os = @import("root").os;
const config = @import("config");

const log = @import("lib").output.log.scoped(.{
    .prefix = "kepler/tests",
    .filter = null,
}).write;

/// IPC test server thread
pub fn ipcServerThread(mailbox: *os.kepler.ipc.Mailbox, test_task: *os.thread.Task) !void {
    var msg: os.kepler.ipc.Message = undefined;
    // Do config.kernel.kepler.bench_msg_count recieve operations
    var i: usize = 0;
    while (i < config.kernel.kepler.bench_msg_count) : (i += 1) {
        mailbox.recieve(&msg);
    }
    // Signal to the main task thread
    os.thread.scheduler.wake(test_task);
}

/// IPC test client thread
pub fn ipcClientThread(token: *os.kepler.ipc.Token) !void {
    var msg: os.kepler.ipc.Message = undefined;
    // Do config.kernel.kepler.bench_msg_count send operations
    var i: usize = 0;
    while (i < config.kernel.kepler.bench_msg_count) : (i += 1) {
        while (true) {
            token.send(&msg) catch {
                os.thread.scheduler.yield();
                continue;
            };
            break;
        }
    }
}

/// IPC test
pub fn ipcTest() !void {
    // Create mailbox
    const mailbox = try os.kepler.ipc.Mailbox.create(os.memory.pmm.phys_heap, 1024);
    log(.info, "Created mailbox!", .{});

    // Create token
    const token = try os.kepler.ipc.Token.create(os.memory.pmm.phys_heap, mailbox, 1024, 69);
    log(.info, "Created token!", .{});

    // Start server thread
    try os.thread.scheduler.spawnTask("IPC test server", ipcServerThread, .{ mailbox, os.platform.get_current_task() });

    // Start client thread
    try os.thread.scheduler.spawnTask("IPC test client", ipcClientThread, .{token});

    log(.info, "Finished spawning tasks", .{});

    os.thread.scheduler.wait();
    token.shutdown();
    mailbox.shutdown();

    log(.info, "IPC test done", .{});
}

/// Run tests
pub fn run() void {
    os.vital(ipcTest(), "IPC test failed");
}
