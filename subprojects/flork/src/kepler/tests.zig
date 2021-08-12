usingnamespace @import("root").preamble;

/// IPC test
pub fn ipc_test() !void {
    // Create mailbox
    const mailbox = try os.kepler.ipc.Mailbox.create(os.memory.pmm.phys_heap, 1);
    os.log("Created mailbox!\n", .{});

    // Create token
    const token = try os.kepler.ipc.Token.create(os.memory.pmm.phys_heap, mailbox, 1, 69);
    os.log("Created token!\n", .{});

    // Send msg to the token
    const payload = "Hello, IPC world!";
    var msg: os.kepler.ipc.Message = undefined;
    std.mem.copy(u8, &msg.data, payload);

    try token.send(&msg);

    // Recieve message
    var recieved: os.kepler.ipc.Message = undefined;
    mailbox.recieve(&recieved);
    const recv_string = (&recieved.data)[0..payload.len];
    //std.debug.assert(std.mem.eql(u8, recv_string, payload));
    os.log("Recieved msg \"{s}\"\n", .{recv_string});

    // Shutdown token
    token.shutdown();

    // Shutdown mailbox
    mailbox.shutdown();

    os.log("IPC tests finished\n", .{});
}

/// Run tests
pub fn run() void {
    os.vital(ipc_test(), "IPC test failed");
}
