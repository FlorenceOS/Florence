# Florence OS

Florence OS is aimed at developers and service providers more than your average user. This isn't for your new facebook machine, but it should be configurable to be just that.
It's just a runtime for your applications can have access to only the things you provide them, providing true separation where needed.

Its goals include but is not limited to:
* Pass around objects instead of using methods filesystem permissions. Some examples may be:
  * If you have an image decoder, it gets a byte array as input, and provides something which satisfies your concept of a decoded image.
  * Your text editor gets only a (possibly modifiable and resizable) byte array and some way to draw things to the screen
* Software should be able to pass on its permissions to other software it is allowed to call
* Remove string semantics where possible. Strings are almost always handled or parsed incorrectly.
* Build your application for running in userspace. Isolate your browser from your network stack in separate processes. Or don't. Build and statically link everything to the kernel if you like.
  * The implementer should be able to write their own effective replacement of `/sbin/init` (with libraries for writing very consise code) something like this (pseudocode with ziglike syntax)
     ```
     import kernel, ahci, echfs, smb;
     kernel.addService(ahci);
     const storage_drive = kernel.disk_by_uuid("abcdef-ghij");
     const my_fs = echfs(.Kernel).from_partition(storage_drive.partitions[0]);
     
     const managment_process = kernel.addProcess(
        .services = .{
            // smb library can know at compile time it's building for userspace with an fs in kernel, which makes it do syscalls to access the filesystem.
            .smb = smb(my_fs);
        },
     );
     ```
  * These kind of files of course should be composable in some way. If someone writes a more complicated combined service which takes a couple of inputs, you should be able to use it in your config here, just like calling any function in any programming language.
