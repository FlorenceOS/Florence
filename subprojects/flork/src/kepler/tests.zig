usingnamespace @import("root").preamble;
const kepler = os.kepler;

const tries = 1_000_000;

fn keplerAssert(condition: bool, comptime panic_msg: []const u8) void {
    if (!condition) @panic("kepler tests failed: " ++ panic_msg);
}

fn server_task(allocator: *std.mem.Allocator, server_noteq: *kepler.ipc.NoteQueue) !void {
    // Server note queue should get the .Request note
    server_noteq.wait();
    const connect_note = server_noteq.tryRecv() orelse unreachable;
    keplerAssert(connect_note.typ == .request_pending, "Not .request_pending node was recieved");
    const conn = connect_note.owner_ref.stream.borrow();
    connect_note.drop();
    os.log(".Request note recieved!\n", .{});

    // Accept the requests
    try connect_note.owner_ref.stream.accept();
    os.log("Request was accepted!\n", .{});

    // Test `tries` requests
    var i: usize = 0;
    var server_send_rdtsc: u64 = 0;
    var server_recv_rdtsc: u64 = 0;
    os.log("Server task enters stress test!\n", .{});
    while (i < tries) : (i += 1) {
        // Server should get .Submit note
        server_noteq.wait();

        const recv_starting_time = os.platform.clock();
        const submit_note = server_noteq.tryRecv() orelse unreachable;
        server_recv_rdtsc += os.platform.clock() - recv_starting_time;

        keplerAssert(submit_note.typ == .tasks_available, "Not .tasks_available node was recieved");
        keplerAssert(
            submit_note.owner_ref.stream == conn,
            "Owning stream ref is incorrect in server task",
        );

        // Allow client to resent its note
        submit_note.drop();
        conn.unblock(.consumer);

        // Notify consumer about completed tasks
        const send_starting_time = os.platform.clock();
        try conn.notify(.consumer);
        server_send_rdtsc += os.platform.clock() - send_starting_time;
    }
    os.log(
        "Server task exits stress test! Send: {} clk. Recieve: {} clk\n",
        .{ server_send_rdtsc / tries, server_recv_rdtsc / tries },
    );

    // Terminate connection from the server
    conn.abandon(.producer);
    os.log("Connection terminated from the server side!\n", .{});
    // Terminate notification queue
    server_noteq.terminate();
}

fn client_task(
    allocator: *std.mem.Allocator,
    client_noteq: *kepler.ipc.NoteQueue,
    endpoint: *kepler.ipc.Endpoint,
) !void {
    // Stream connection object
    const conn_params = kepler.ipc.Stream.UserspaceInfo{
        .consumer_rw_buf_size = 1024,
        .producer_rw_buf_size = 1024,
        .obj_mailbox_size = 16,
    };
    const conn = try kepler.ipc.Stream.create(allocator, client_noteq, endpoint, conn_params);
    os.log("Created connection!\n", .{});

    // Client note queue should get the .Accept note
    client_noteq.wait();
    const accept_note = client_noteq.tryRecv() orelse unreachable;
    keplerAssert(accept_note.typ == .request_accepted, "Not .request_accepted node was recieved");
    keplerAssert(
        accept_note.owner_ref.stream == conn,
        "Owner stream reference is incorrect in client task on request_accepted event",
    );
    accept_note.drop();
    os.log(".Accept note recieved!\n", .{});

    // Finalize accept/request sequence
    conn.finalizeConnection();
    os.log("Connection finalized!\n", .{});

    // Test `tries` requests
    var i: usize = 0;
    var client_send_rdtsc: usize = 0;
    var client_recv_rdtsc: usize = 0;
    os.log("Client task enters stress test!\n", .{});
    while (i < tries) : (i += 1) {
        // Let's notify server about more tasks
        const send_starting_time = os.platform.clock();
        try conn.notify(.producer);
        client_send_rdtsc += os.platform.clock() - send_starting_time;

        // Client should get .Complete note
        client_noteq.wait();

        const recv_starting_time = os.platform.clock();
        const complete_note = client_noteq.tryRecv() orelse unreachable;
        client_recv_rdtsc += os.platform.clock() - recv_starting_time;

        keplerAssert(
            complete_note.typ == .results_available,
            "Not .results_available note was recieved",
        );
        keplerAssert(
            complete_note.owner_ref.stream == conn,
            "Incorrect owning stream ref in client task",
        );
        complete_note.drop();

        // Allow server to resend its note
        conn.unblock(.producer);
    }
    os.log(
        "Client task exits stress test! Send: {} clk. Recieve: {} clk\n",
        .{ client_send_rdtsc / tries, client_recv_rdtsc / tries },
    );

    // Client should get ping of death message
    client_noteq.wait();
    const server_death_note = client_noteq.tryRecv() orelse unreachable;
    keplerAssert(
        server_death_note.owner_ref.stream == conn,
        "Incorrect owning stream ref on ping of death",
    );
    keplerAssert(
        server_death_note.typ == .producer_left,
        "Note type on ping of death is not .producer_left",
    );
    os.log("Ping of death recieved!\n", .{});
    server_death_note.drop();

    // Close connection on the client's side as well
    conn.abandon(.consumer);
    os.log("Connection terminated from the client side!\n", .{});

    // Terminate notification queue
    client_noteq.terminate();

    // Exit client task
    os.thread.scheduler.exitTask();
}

fn notificationsStressTest(allocator: *std.mem.Allocator) !void {
    os.log("\nNotifications test...\n", .{});
    // Server notificaiton queue
    const server_noteq = try kepler.ipc.NoteQueue.create(allocator);
    os.log("Created server queue!\n", .{});
    // Client notification queue
    const client_noteq = try kepler.ipc.NoteQueue.create(allocator);
    os.log("Created client queue!\n", .{});
    // Server endpoint
    const endpoint = try kepler.ipc.Endpoint.create(allocator, server_noteq);
    os.log("Created server endpoint!\n", .{});

    // Run client task separately
    try os.thread.scheduler.spawnTask(client_task, .{ allocator, client_noteq, endpoint });

    // Launch server task inline
    try server_task(allocator, server_noteq);
    os.log("Server has terminated! Let's hope that client would finish as needed", .{});
}

fn rejectionTest(allocator: *std.mem.Allocator) !void {
    os.log("\nRejection test...\n", .{});
    // Server notificaiton queue
    const server_noteq = try kepler.ipc.NoteQueue.create(allocator);
    os.log("Created server queue!\n", .{});
    // Client notification queue
    const client_noteq = try kepler.ipc.NoteQueue.create(allocator);
    os.log("Created client queue!\n", .{});
    // Server endpoint
    const endpoint = try kepler.ipc.Endpoint.create(allocator, server_noteq);
    os.log("Created server endpoint!\n", .{});
    // Stream connection object
    const conn_params = kepler.ipc.Stream.UserspaceInfo{
        .consumer_rw_buf_size = 1024,
        .producer_rw_buf_size = 1024,
        .obj_mailbox_size = 16,
    };
    const conn = try kepler.ipc.Stream.create(allocator, client_noteq, endpoint, conn_params);
    os.log("Created connection!\n", .{});
    // Get .Request note
    server_noteq.wait();
    const connect_note = server_noteq.tryRecv() orelse unreachable;
    keplerAssert(connect_note.typ == .request_pending, "Not .request_pending node was recieved");
    const server_conn = connect_note.owner_ref.stream.borrow();
    connect_note.drop();
    os.log("Request recieved\n", .{});
    // Reject connection
    server_conn.abandon(.producer);
    os.log("Connection denied\n", .{});
    // Client should get .request_denied note
    client_noteq.wait();
    const denied_note = client_noteq.tryRecv() orelse unreachable;
    keplerAssert(denied_note.typ == .request_denied, "Not .request_denied note was recieved");
    denied_note.drop();
    os.log("Request denied note was recieved!\n", .{});
    conn.drop();
    server_noteq.terminate();
    client_noteq.terminate();
}

fn lateAcceptTest(allocator: *std.mem.Allocator) !void {
    os.log("\nLate accept test...\n", .{});
    // Server notificaiton queue
    const server_noteq = try kepler.ipc.NoteQueue.create(allocator);
    os.log("Created server queue!\n", .{});
    // Client notification queue
    const client_noteq = try kepler.ipc.NoteQueue.create(allocator);
    os.log("Created client queue!\n", .{});
    // Server endpoint
    const endpoint = try kepler.ipc.Endpoint.create(allocator, server_noteq);
    os.log("Created server endpoint!\n", .{});
    // Stream connection object
    const conn_params = kepler.ipc.Stream.UserspaceInfo{
        .consumer_rw_buf_size = 1024,
        .producer_rw_buf_size = 1024,
        .obj_mailbox_size = 16,
    };
    const conn = try kepler.ipc.Stream.create(allocator, client_noteq, endpoint, conn_params);
    os.log("Created connection!\n", .{});
    // Get .Request note
    server_noteq.wait();
    const connect_note = server_noteq.tryRecv() orelse unreachable;
    keplerAssert(connect_note.typ == .request_pending, "Not .request_pending node was recieved");
    const server_conn = connect_note.owner_ref.stream.borrow();
    connect_note.drop();
    os.log("Request recieved\n", .{});
    // Shutdown connection from consumer
    conn.abandon(.consumer);
    // Send accept note
    if (server_conn.accept()) {
        @panic("No error in late accept test");
    } else |err| {
        keplerAssert(err == error.NotPending, "Not error.NotPending");
    }
    os.log("Thread unreachable error was recieved\n", .{});
    conn.abandon(.producer);
    client_noteq.terminate();
    server_noteq.terminate();
}

fn memoryObjectsTest(allocator: *std.mem.Allocator) !void {
    os.log("\nMemory objects test...\n", .{});
    // Get page size
    const page_size = kepler.memory.getSmallestPageSize();
    // Create plain memory object
    const test_obj = try kepler.memory.MemoryObjectRef.createPlain(
        allocator,
        page_size * 10,
        page_size,
        kepler.memory.MemoryPerms.rw(),
    );
    os.log("Created memory object of size 0x10000!\n", .{});
    // Allocate space in non-paged pool
    const fake_arr = try os.memory.vmm.nonbacked().allocFn(
        os.memory.vmm.nonbacked(),
        0x10000,
        1,
        1,
        0,
    );
    const base = @ptrToInt(fake_arr.ptr);
    // Try to map memory object
    try test_obj.mapIn(.{
        .context = &os.memory.paging.kernel_context,
        .base = base,
        .offset = 0,
        .size = page_size * 10,
        .perms = kepler.memory.MemoryPerms.rw(),
        .user = false,
        .memtype = .MemoryWriteBack,
    });
    os.log("Mapped memory object!\n", .{});
    const arr = @intToPtr([*]u8, base);
    arr[0] = 0x69;
    test_obj.unmapFrom(.{
        .context = &os.memory.paging.kernel_context,
        .base = base,
        .size = page_size * 10,
    });
    os.log("Unmapped memory object!\n", .{});
    // Map memory object again
    try test_obj.mapIn(.{
        .context = &os.memory.paging.kernel_context,
        .base = base,
        .offset = 0,
        .size = page_size * 10,
        .perms = kepler.memory.MemoryPerms.rw(),
        .user = false,
        .memtype = .MemoryWriteBack,
    });
    os.log("Mapped memory object again!\n", .{});
    keplerAssert(arr[0] == 0x69, "Value passed in shared memory was not preserved");
    test_obj.unmapFrom(.{
        .context = &os.memory.paging.kernel_context,
        .base = base,
        .size = page_size * 10,
    });
    os.log("Unmapped memory object again!\n", .{});

    test_obj.drop();
    os.log("Dropped memory object!\n", .{});

    _ = os.memory.vmm.nonbacked().resizeFn(
        os.memory.vmm.nonbacked(),
        fake_arr,
        1,
        0,
        1,
        0,
    ) catch @panic("Unmap failed");
}

fn objectPassingTest(allocator: *std.mem.Allocator) !void {
    os.log("\nObject passing test...\n", .{});

    var mailbox = try kepler.objects.ObjectRefMailbox.init(allocator, 2);
    os.log("Created object reference mailbox!\n", .{});

    // Get smallest page size
    const page_size = kepler.memory.getSmallestPageSize();
    // Create a dummy object to pass around
    const test_obj = try kepler.memory.MemoryObjectRef.createPlain(
        allocator,
        page_size * 10,
        page_size,
        kepler.memory.MemoryPerms.rwx(),
    );
    os.log("Created dummy object!\n", .{});
    const dummy_ref = kepler.objects.ObjectRef{ .memory_object = test_obj };

    // Test send from consumer and recieve from producer
    if (mailbox.writeFromConsumer(3, dummy_ref)) {
        @panic("Mailbox should have returned out of bounds error");
    } else |err| {
        keplerAssert(
            err == error.OutOfBounds,
            "Error returned from mailbox is not out of bounds error",
        );
    }
    os.log("Out of bounds write passed!\n", .{});

    try mailbox.writeFromConsumer(0, dummy_ref);
    os.log("Send passed!\n", .{});

    if (mailbox.writeFromConsumer(0, dummy_ref)) {
        @panic("Mailbox should not have permitted write to the same cell");
    } else |err| {
        keplerAssert(
            err == error.NotEnoughPermissions,
            "Error returned from mailbox is not NotEnoughPermissions",
        );
    }
    os.log("Wrong send to the same cell passed!\n", .{});

    if (mailbox.readFromProducer(1)) |_| {
        @panic("Read with wrong permissions should not be permitted");
    } else |err| {
        keplerAssert(
            err == error.NotEnoughPermissions,
            "Error returned from mailbox is not NotEnoughPermissions",
        );
    }
    os.log("Read with wrong permissions passed!\n", .{});

    const recieved_dummy_ref = try mailbox.readFromProducer(0);
    keplerAssert(
        recieved_dummy_ref.memory_object.val == dummy_ref.memory_object.val,
        "The reference to the object passed is corrupted",
    );
    recieved_dummy_ref.drop();
    os.log("Read passed!\n", .{});

    // Test grant from consumer, send from producer, and reciever from consumer
    try mailbox.grantWritePerms(0);

    if (mailbox.writeFromProducer(1, dummy_ref)) {
        @panic("Write permission violation was not detected");
    } else |err| {
        keplerAssert(
            err == error.NotEnoughPermissions,
            "Error returned from mailbox is not NotEnoughPermissions",
        );
    }
    os.log("Write with wrong permissions passed!\n", .{});

    try mailbox.writeFromProducer(0, dummy_ref);

    const new_recieved_dummy_ref = try mailbox.readFromConsumer(0);
    keplerAssert(
        new_recieved_dummy_ref.memory_object.val == dummy_ref.memory_object.val,
        "The reference to the object passed is corrupted",
    );
    new_recieved_dummy_ref.drop();
    os.log("Read passed!\n", .{});

    dummy_ref.drop();
    mailbox.drop();
}

fn lockedHandlesTest(allocator: *std.mem.Allocator) !void {
    os.log("\nLocked handles test...\n", .{});
    // Create test notification queue
    const noteq = try kepler.ipc.NoteQueue.create(allocator);
    os.log("Notification queue created...\n", .{});
    const handle = try kepler.objects.LockedHandle.create(allocator, 69, 420, noteq);
    // Try to peek with various password values
    keplerAssert((try handle.peek(420)) == 69, "Failed to open locked handle");
    if (handle.peek(412)) |_| {
        @panic("Authentification failure was not caught");
    } else |err| {
        keplerAssert(
            err == error.AuthenticationFailed,
            "Wrong error was returned from handle.peek",
        );
    }
    os.log("Peek tests passed...\n", .{});
    // Try to drop locked handle
    handle.drop();
    // Assert correct notification type
    const death_note = noteq.tryRecv() orelse unreachable;
    keplerAssert(death_note.typ == .locked_handle_unreachable, "Wrong notification type");
    os.log("Death ping recieved...\n", .{});
    noteq.terminate();
    os.log("Queue shutdown successful...\n", .{});
    os.log("Locked handles test passed...\n", .{});
}

fn lockedHandleTableTest(allocator: *std.mem.Allocator) !void {
    const Table = lib.containers.handle_table.LockedHandleTable(u64, os.thread.Mutex);

    os.log("\nLocked handle table test...\n", .{});
    var instance: Table = .{};
    instance.init(allocator);

    const result1 = try instance.newCell();
    result1.ref.* = 69;
    keplerAssert(result1.id == 0, "Allocated handle is not 0");

    instance.unlock();
    os.log("First alloc done!...\n", .{});

    const result2 = try instance.newCell();
    result2.ref.* = 420;
    keplerAssert(result2.id == 1, "Allocated handle is not 1");

    instance.unlock();
    os.log("Second alloc done!...\n", .{});

    const TestDisposer = struct {
        called: u64,

        pub fn init() @This() {
            return .{ .called = 0 };
        }

        pub fn dispose(
            self: *@This(),
            loc: Table.Location,
        ) void {
            self.called += 1;
        }
    };

    var disposer = TestDisposer.init();
    os.log("Disposing handle table...\n", .{});
    instance.deinit(TestDisposer, &disposer);
    keplerAssert(disposer.called == 2, "The disposer function wasn't called two times");
}

fn interruptTest(allocator: *std.mem.Allocator) !void {
    os.log("\nInterrupt test...\n", .{});
    // Create a notification queue
    const noteq = try kepler.ipc.NoteQueue.create(allocator);
    // Create interrupt object
    var object: kepler.interrupts.InterruptObject = undefined;
    const dummy_callback = struct {
        fn dummy(_: *kepler.interrupts.InterruptObject) void {}
    }.dummy;
    object.init(noteq, dummy_callback, dummy_callback);
    // Raise interrupt
    object.raise();
    // Check that we got a notification
    const note = noteq.tryRecv() orelse unreachable;
    keplerAssert(note.typ == .interrupt_raised, "Note raised on interrupt has incorrect type");
    note.drop();
    object.shutdown();
}

pub fn run_tests() !void {
    var buffer: [4096]u8 = undefined;
    var fixed_buffer = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = &fixed_buffer.allocator;

    try notificationsStressTest(allocator);
    try rejectionTest(allocator);
    try lateAcceptTest(allocator);
    try memoryObjectsTest(allocator);
    try objectPassingTest(allocator);
    try lockedHandlesTest(allocator);
    try lockedHandleTableTest(allocator);
    try interruptTest(allocator);

    os.log("\nAll tests passing!\n", .{});
}
