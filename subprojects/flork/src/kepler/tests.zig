usingnamespace @import("root").preamble;

/// RPC test client
fn rpcTestClient(
    entry: *os.kepler.entry.Entry,
    hmailbox: usize,
    hcaller: usize,
    hcallee: usize,
    main_task: *os.thread.Task,
) !void {
    var i: usize = 0;
    os.log("client: entering loop\n", .{});
    while (i < config.kernel.kepler.bench_msg_count) : (i += 1) {
        var msg = os.kepler.rpc.Message{};
        msg.opaque_val = 2 * i;
        // Initiate RPC call
        try entry.sysDoRemoteCall(hcaller, hcallee, &msg);
        // os.log("client: initiated RPC call #{}\n", .{i});
        // Wait for incoming notifications
        const note = try entry.sysGetNotification(hmailbox);
        // os.log("client: recieved notification for reply to RPC call #{}\n", .{i});
        std.debug.assert(note.kind == .RPCReply);
        std.debug.assert(note.opaque_val == 1);
        // Recieve reply
        const recieved = try entry.sysGetRemoteCallReply(hcaller, &msg);
        std.debug.assert(msg.opaque_val == 2 * i);
        // os.log("client: reply recieved for RPC call #{}\n", .{i});
    }
    os.log("client: exiting loop\n", .{});
    // Deinitialize user API entry
    entry.deinit();
    os.log("client: finished\n", .{});
}

/// RPC test server
fn rpcTestServer(entry: *os.kepler.entry.Entry, hmailbox: usize, hcallee: usize) !void {
    var i: usize = 0;
    os.log("server: entering loop\n", .{});
    while (i < config.kernel.kepler.bench_msg_count) : (i += 1) {
        var msg: os.kepler.rpc.Message = undefined;
        // Wait for incoming notifications
        const note = try entry.sysGetNotification(hmailbox);
        // os.log("server: recieved notification for RPC call #{}\n", .{i});
        std.debug.assert(note.kind == .RPCIncoming);
        std.debug.assert(note.opaque_val == 2);
        // Accept incoming RPC call
        try entry.sysAcceptRemoteCall(hcallee, &msg);
        // os.log("server: RPC call #{} accepted\n", .{i});
        // Send reply
        try entry.sysReturnRemoteCall(hcallee, msg.opaque_val, &msg);
        // os.log("server: returned RPC call #{}\n", .{i});
    }
    os.log("server: exiting loop\n", .{});
    // Wait for shutdown notification
    const note = try entry.sysGetNotification(hmailbox);
    std.debug.assert(note.kind == .CalleeLost);
    os.log("server: got shutdown note\n", .{});
    // Deinitialize user API entry
    entry.deinit();
    os.log("server: finished\n", .{});
}

/// RPC test
fn rpcTest() !void {
    // Get our hands on allocator
    const allocator = os.memory.pmm.phys_heap;
    // Create user API entries
    var entry1 = try os.kepler.entry.Entry.init(allocator);
    var entry2 = try os.kepler.entry.Entry.init(allocator);
    os.log("User API entries initialized\n", .{});
    // Create mailbox
    const hmailbox1 = try entry1.sysCreateMailbox(1);
    const hmailbox2 = try entry2.sysCreateMailbox(2);
    os.log("Created mailboxes\n", .{});
    // Create caller in first universe
    const hcaller = try entry1.sysCreateCaller(hmailbox1, 1, 1);
    os.log("Created caller\n", .{});
    // Create callee pair in second universe
    const callee_pair = try entry2.sysCreateCallee(hmailbox2, 1, 2);
    const hcallee_owning = callee_pair.owning_handle;
    os.log("Created callee\n", .{});
    // Move consumer handle from one universe to the other
    const callee_ref = try entry2.universe.takeAtNolock(callee_pair.consumer_handle);
    const hcallee_borrowed = try entry1.universe.putNolock(callee_ref);
    os.log("We did a little trolling with borrowed handle\n", .{});
    // Spawn tasks
    const current = os.platform.get_current_task();
    try os.thread.scheduler.spawnTask(rpcTestClient, .{ &entry1, hmailbox1, hcaller, hcallee_borrowed, current });
    try os.thread.scheduler.spawnTask(rpcTestServer, .{ &entry2, hmailbox2, hcallee_owning });
    os.log("Tasks created\n", .{});
    // Wait for test completition
    os.thread.scheduler.wait();
    os.log("RPC test done\n", .{});
}

/// Run tests
pub fn run() void {
    os.vital(rpcTest(), "RPC test failed");
}
