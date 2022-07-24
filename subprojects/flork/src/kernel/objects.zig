const os = @import("root").os;

const lib = @import("lib");
const object = lib.obj.object;

const log = @import("lib").output.log.scoped(.{
    .prefix = "kernel/objects",
    .filter = null,
});

const GlobalRoot = struct {
    obj: object.Object = object.init(@This(), "obj"),

    pub fn requestYank(_: *@This()) !void {
        return error.YankGlobalRoot;
    }

    pub fn commitYank(_: *@This()) void {
        @panic("commit root yank");
    }

    pub fn abortYank(_: *@This()) void {
        @panic("abort root yank");
    }

    pub fn instantYank(_: *@This()) void {
        @panic("instant root yank");
    }

    pub fn print(_: *@This(), fmt: anytype) void {
        fmt("Global root object", .{});
    }
};

// The global object cannot have any siblings
var root_object = GlobalRoot{};
const root_obj = &root_object.obj;

fn printObjAtIndentation(obj: *object.Object, indent: usize) void {
    obj.lock();
    defer obj.unlock();

    const l = log.start(null, "", .{});

    var curr_indent: usize = 0;
    while(curr_indent < indent) : (curr_indent += 1) {
        log.cont(null, " ", .{}, l);
    }

    log.finish(null, "{}", .{obj}, l);

    var child = obj.first_child;
    while(child) |c| : (child = c.next_sibling) {
        printObjAtIndentation(c, indent + 1);
    }
}

var print_obj_semaphore = os.thread.Semaphore{.available = 0};

fn printObjTask() void {
    while(true) {
        print_obj_semaphore.acquire(1);
        printObjAtIndentation(root_obj, 0);
    }
}

pub fn launchPrintTask() void {
    os.thread.scheduler.spawnTask("Object printing task", printObjTask, .{ }) catch @panic("Could not launch object printer");
}

// Print async, safe to call from interrupt context
pub fn printObjTree() void {
    print_obj_semaphore.release(1);
}

pub fn addGlobalObj(obj: *object.Object) void {
    root_obj.lock();
    defer obj.unlock();

    root_obj.addChild(obj);
}
