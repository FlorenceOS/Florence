usingnamespace @import("root").preamble;

/// IPC test client
fn ipcTestClient(
    mailbox: *os.kepler.notifications.Mailbox,
    own_token: *os.kepler.ipc.Token,
    remote_token: *os.kepler.ipc.Token,
    main_task: *os.thread.Task,
) !void {
    var i: usize = 0;
    os.log("client: entering loop\n", .{});
    while (i < config.kernel.kepler.bench_msg_count) : (i += 1) {
        var msg = os.kepler.ipc.Message{};
        // Send message
        try remote_token.send(&msg);
        os.log("client: sent message #{}\n", .{i});
        // Wait for incoming notifications
        const note = try mailbox.dequeue();
        os.log("client: recieved notification for message #{}\n", .{i});
        // Recieve message
        const recieved = try own_token.recieve(&msg);
        std.debug.assert(recieved);
        os.log("client: reply recieved for message #{}\n", .{i});
    }
    os.log("client: exiting loop\n", .{});
    remote_token.shutdownFromProducer();
    // Wait for token shutdown notification
    const note = try mailbox.dequeue();
    std.debug.assert(note.kind == .TokenUpdate);
    os.log("client: got shutdown note\n", .{});
    // Shutdown all refs
    mailbox.shutdown();
    own_token.shutdownFromConsumer();
    os.thread.scheduler.wake(main_task);
    os.log("client: finished\n", .{});
}

/// IPC test server
fn ipcTestServer(
    mailbox: *os.kepler.notifications.Mailbox,
    own_token: *os.kepler.ipc.Token,
    remote_token: *os.kepler.ipc.Token,
) !void {
    var i: usize = 0;
    os.log("server: entering loop\n", .{});
    while (i < config.kernel.kepler.bench_msg_count) : (i += 1) {
        var msg: os.kepler.ipc.Message = undefined;
        // Wait for incoming notifications
        const note = try mailbox.dequeue();
        os.log("server: recieved notification for request #{}\n", .{i});
        // Recieve message
        const recieved = try own_token.recieve(&msg);
        std.debug.assert(recieved);
        os.log("client: request #{} recieved\n", .{i});
        // Send reply
        try remote_token.send(&msg);
        os.log("client: sent reply to request #{}\n", .{i});
    }
    os.log("server: exiting loop\n", .{});
    remote_token.shutdownFromProducer();
    // Wait for token shutdown notification
    const note = try mailbox.dequeue();
    std.debug.assert(note.kind == .TokenUpdate);
    os.log("server: got shutdown note\n", .{});
    // Shutdown all refs
    mailbox.shutdown();
    own_token.shutdownFromConsumer();
    os.log("server: finished\n", .{});
}

/// IPC test
fn ipcTest() !void {
    // Get our hands on allocator
    const allocator = os.memory.pmm.phys_heap;
    // Create mailboxes
    const mailbox1 = try os.kepler.notifications.Mailbox.create(allocator, 1);
    const mailbox2 = try os.kepler.notifications.Mailbox.create(allocator, 1);
    // Create tokens
    const token1 = try os.kepler.ipc.Token.create(allocator, mailbox1, 1, 69);
    const token2 = try os.kepler.ipc.Token.create(allocator, mailbox2, 1, 69);
    // Spawn tasks
    const current = os.platform.get_current_task();
    try os.thread.scheduler.spawnTask(ipcTestClient, .{
        mailbox1,
        token1.borrow(),
        token2.borrow(),
        current,
    });
    try os.thread.scheduler.spawnTask(ipcTestServer, .{ mailbox2, token2, token1 });
    // Wait for test completition
    os.thread.scheduler.wait();
    os.log("IPC test done\n", .{});
}

/// Run tests
pub fn run() void {
    os.vital(ipcTest(), "IPC test failed");
}
