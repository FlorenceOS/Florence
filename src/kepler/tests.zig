const std = @import("std");
const os = @import("root").os;
const kepler = os.kepler;

fn notifications() !void {
    os.log("\nNotifications test...\n", .{});
    var buffer: [4096]u8 = undefined;
    var fixed_buffer = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = &fixed_buffer.allocator;
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
    const conn = try kepler.ipc.Stream.create(allocator, client_noteq, endpoint);
    os.log("Created connection!\n", .{});
    // Server note queue should get the .Request note
    const connect_note = server_noteq.try_recv() orelse unreachable;
    std.debug.assert(connect_note.typ == .RequestPending);
    std.debug.assert(connect_note.owner_ref.stream == conn);
    os.log(".Request note recieved!\n", .{});
    // Accept the request
    try connect_note.owner_ref.stream.accept();
    os.log("Request was accepted!\n", .{});
    // Client note queue should get the .Accept note
    const accept_note = client_noteq.try_recv() orelse unreachable;
    std.debug.assert(accept_note.typ == .RequestAccepted);
    std.debug.assert(accept_note.owner_ref.stream == conn);
    accept_note.drop();
    os.log(".Accept note recieved!\n", .{});
    // Finalize accept/request sequence
    conn.finalize_connection();
    os.log("Connection finalized!\n", .{});
    // Let's notify server about more tasks
    try conn.notify(.Producer);
    os.log("Producer was notified!\n", .{});
    // Try again to test if resend is handled
    try conn.notify(.Producer);
    os.log("Producer was notified again!\n", .{});
    // Server should get .Submit note
    const submit_note = server_noteq.try_recv() orelse unreachable;
    std.debug.assert(submit_note.typ == .TasksAvailable);
    std.debug.assert(submit_note.owner_ref.stream == conn);
    os.log("Server recieved .Submit note!\n", .{});
    // Allow client to resent its note
    conn.unblock(.Consumer);
    submit_note.drop();
    // Notify consumer about completed tasks
    try conn.notify(.Consumer);
    // Client should get .Complete note
    const complete_note = client_noteq.try_recv() orelse unreachable;
    std.debug.assert(complete_note.typ == .ResultsAvailable);
    std.debug.assert(submit_note.owner_ref.stream == conn);
    os.log("Client recieved .Submit note!\n", .{});
    // Allow server to resend its note
    conn.unblock(.Producer);
    complete_note.drop();
    // Terminate connection from the server
    conn.abandon(.Producer);
    os.log("Connection terminated from the server side!\n", .{});
    // Client should get ping of death message
    const server_death_note = client_noteq.try_recv() orelse unreachable;
    std.debug.assert(submit_note.owner_ref.stream == conn);
    std.debug.assert(server_death_note.typ == .ProducerLeft);
    os.log("Ping of death recieved!\n", .{});
    complete_note.drop();
    // Close connection on the client's side as well
    conn.abandon(.Consumer);
    os.log("Connection terminated from the client side!\n", .{});
}

fn memory_objects() !void {
    os.log("\nMemory objects test...\n", .{});
    var buffer: [4096]u8 = undefined;
    var fixed_buffer = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = &fixed_buffer.allocator;

    const test_obj = try kepler.memory.MemoryObject.create(allocator, 0x10000);
    os.log("Created memory object of size 0x10000!\n", .{});
    const base = try kepler.memory.kernel_mapper.map(test_obj, os.memory.paging.rw(), .MemoryWriteBack);
    os.log("Mapped memory object!\n", .{});
    const arr = @intToPtr([*]u8, base);
    arr[0] = 0x69;
    kepler.memory.kernel_mapper.unmap(test_obj, base);
    os.log("Unmapped memory object!\n", .{});

    const base2 = try kepler.memory.kernel_mapper.map(test_obj, os.memory.paging.ro(), .MemoryWriteBack);
    os.log("Mapped memory object again!\n", .{});
    const arr2 = @intToPtr([*]u8, base2);
    std.debug.assert(arr2[0] == 0x69);
    kepler.memory.kernel_mapper.unmap(test_obj, base2);
    os.log("Unmapped memory object again!\n", .{});

    test_obj.drop();
    os.log("Dropped memory object!\n", .{});
}

fn object_passing() !void {
    os.log("\nObject passing test...\n", .{});
    var buffer: [4096]u8 = undefined;
    var fixed_buffer = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = &fixed_buffer.allocator;

    const mailbox = try kepler.objects.ObjectRefMailbox.create(allocator, 2);
    os.log("Created object reference mailbox!\n", .{});

    // Create a dummy object to pass around
    const dummy = try kepler.memory.MemoryObject.create(allocator, 0x1000);
    os.log("Created dummy object!\n", .{});
    const dummy_ref = kepler.objects.ObjectRef { .MemoryObject = .{ .ref = dummy.borrow(), .mapped_to = null } };

    // Test send from consumer and recieve from producer
    if (mailbox.write_from_consumer(3, dummy_ref)) {
        unreachable;
    } else |err| { 
        std.debug.assert(err == error.OutOfBounds); 
    }
    os.log("Out of bounds write passed!\n", .{});

    try mailbox.write_from_consumer(0, dummy_ref);
    os.log("Send passed!\n", .{});

    if (mailbox.write_from_consumer(0, dummy_ref)) {
        unreachable;
    } else |err| { 
        std.debug.assert(err == error.NotEnoughPermissions); 
    }
    os.log("Wrong send to the same cell passed!\n", .{});

    if (mailbox.read_from_producer(1)) |_| {
        unreachable;
    } else |err| {
        std.debug.assert(err == error.NotEnoughPermissions); 
    }
    os.log("Read with wrong permissions passed!\n", .{});

    const recieved_dummy_ref = try mailbox.read_from_producer(0);
    std.debug.assert(recieved_dummy_ref.MemoryObject.ref == dummy_ref.MemoryObject.ref);
    recieved_dummy_ref.drop(&kepler.memory.kernel_mapper);
    os.log("Read passed!\n", .{});

    // Test grant from consumer, send from producer, and reciever from consumer
    try mailbox.grant_write(0);

    if (mailbox.write_from_producer(1, dummy_ref)) {
        unreachable;
    } else |err| {
        std.debug.assert(err == error.NotEnoughPermissions); 
    }
    os.log("Write with wrong permissions passed!\n", .{});

    try mailbox.write_from_producer(0, dummy_ref);

    const new_recieved_dummy_ref = try mailbox.read_from_consumer(0);
    std.debug.assert(new_recieved_dummy_ref.MemoryObject.ref == dummy_ref.MemoryObject.ref);
    new_recieved_dummy_ref.drop(&kepler.memory.kernel_mapper);
    os.log("Read passed!\n", .{});

    dummy_ref.drop(&kepler.memory.kernel_mapper);
}

pub fn run_tests() !void {
    try notifications();
    try memory_objects();
    try object_passing();
}
