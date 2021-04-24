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
  * The implementer should be able to write their own effective replacement of `/sbin/init` and `kconfig` (with libraries for writing very consise code) something like this (pseudocode with ziglike syntax). This is somewhat inspired by the design philosophy of NixOS.
    ```
    import kernel, ahci, xhci, ide, disk_multiplexer;

    const storage_services = kernel.services(
      .disks = disk_multiplexer(.{
        .ide  = ide(.AllDrives),
        .ahci = ahci(.AllDrives),
        .xhci = xhci(.StorageDevices),
      }),
    });

    import userspace, disk_identifier, echfs;

    // Some storage provider `storage_services` providing
    // disks objects are now known to exist in the kernel

    const fs_service = userspace.services(.{
      .fs = echfs.use_partition(
        disk_identifier(storage_services.disks)
          .find_by_uuid("abcdef-ghij").partitions[0],
      ),
    });

    import tcp;

    const network_services = kernel.services(
      // Theoretically some set of drivers here too (or
      // a provided default one) but this is just an example
      .tcp = tcp;
    });

    // This server can see that it will communicate with another
    // process over IPC at compile time to access the filesystem,
    // and that the network is in the kernel through syscalls
    const share_server = userspace.services(.{
      .smb_server = smb(.{.fs = fs_service.fs, .tcp = network_services.tcp }),
    });
    ```
  * These kind of files of course should be composable in some way. If someone writes a more complicated combined service which takes a couple of inputs, you should be able to use it in your config here, just like calling any function in any programming language.
