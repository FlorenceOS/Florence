const std = @import("std");
const os = @import("root").os;
const kepler = os.kepler;

pub fn basic() !void {
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