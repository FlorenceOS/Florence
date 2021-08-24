usingnamespace @import("root").preamble;

/// RPC test client
fn rpcTestClient(
    mailbox: *os.kepler.notifications.Mailbox,
    caller: *os.kepler.rpc.Caller,
    callee: *os.kepler.rpc.Callee,
    main_task: *os.thread.Task,
) !void {
    var i: usize = 0;
    os.log("client: entering loop\n", .{});
    while (i < config.kernel.kepler.bench_msg_count) : (i += 1) {
        var msg = os.kepler.rpc.Message{};
        msg.opaque_val = 2 * i;
        // Initiate RPC call
        try caller.sendRPCRequest(callee, &msg);
        // os.log("client: initiated RPC call #{}\n", .{i});
        // Wait for incoming notifications
        const note = try mailbox.dequeue();
        // os.log("client: recieved notification for reply to RPC call #{}\n", .{i});
        std.debug.assert(note.kind == .RPCReply);
        std.debug.assert(note.opaque_val == 1);
        // Recieve reply
        const recieved = try caller.getRPCResponse(&msg);
        std.debug.assert(msg.opaque_val == 2 * i);
        // os.log("client: reply recieved for RPC call #{}\n", .{i});
    }
    os.log("client: exiting loop\n", .{});
    // Drop all refs
    callee.dropBorrowed();
    caller.shutdown();
    mailbox.shutdown();
    os.thread.scheduler.wake(main_task);
    os.log("client: finished\n", .{});
}

/// RPC test server
fn rpcTestServer(mailbox: *os.kepler.notifications.Mailbox, callee: *os.kepler.rpc.Callee) !void {
    var i: usize = 0;
    os.log("server: entering loop\n", .{});
    while (i < config.kernel.kepler.bench_msg_count) : (i += 1) {
        var msg: os.kepler.rpc.Message = undefined;
        // Wait for incoming notifications
        const note = try mailbox.dequeue();
        // os.log("server: recieved notification for RPC call #{}\n", .{i});
        std.debug.assert(note.kind == .RPCIncoming);
        std.debug.assert(note.opaque_val == 2);
        // Accept incoming RPC call
        try callee.acceptRPC(&msg);
        // os.log("server: RPC call #{} accepted\n", .{i});
        // Send reply
        try callee.replyToRPC(msg.opaque_val, &msg);
        // os.log("server: returned RPC call #{}\n", .{i});
    }
    os.log("server: exiting loop\n", .{});
    // Wait for shutdown notification
    const note = try mailbox.dequeue();
    std.debug.assert(note.kind == .CalleeLost);
    os.log("server: got shutdown note\n", .{});
    mailbox.shutdown();
    os.log("server: finished\n", .{});
}

/// RPC test
fn rpcTest() !void {
    // Get our hands on allocator
    const allocator = os.memory.pmm.phys_heap;
    // Create mailboxes
    const mailbox1 = try os.kepler.notifications.Mailbox.create(allocator, 1);
    const mailbox2 = try os.kepler.notifications.Mailbox.create(allocator, 2);
    // Create caller
    const caller = try os.kepler.rpc.Caller.create(allocator, mailbox1, 1, 1);
    // Create callee.
    const callee = try os.kepler.rpc.Callee.create(allocator, mailbox2, 1024, 2);
    // Spawn tasks
    const current = os.platform.get_current_task();
    try os.thread.scheduler.spawnTask(rpcTestClient, .{ mailbox1, caller, callee, current });
    try os.thread.scheduler.spawnTask(rpcTestServer, .{ mailbox2, callee });
    // Wait for test completition
    os.thread.scheduler.wait();
    os.log("RPC test done\n", .{});
}

/// Run tests
pub fn run() void {
    os.vital(rpcTest(), "RPC test failed");
}
