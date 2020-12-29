#include "flo/Assert.hpp"

#include "Kernel/Disk.hpp"

#include "Kernel/Drivers/Disk/AHCI.hpp"

#include "flo/IO.hpp"
#include "flo/Bitfields.hpp"
#include "flo/Kernel.hpp"
#include "flo/Memory.hpp"
#include "flo/Multitasking.hpp"
#include "flo/Util.hpp"
#include "flo/Containers/Monitor.hpp"
#include "flo/Containers/Bitset.hpp"

namespace flo::AHCI {
  namespace {
    constexpr bool quiet = false;
    auto pline = flo::makePline<quiet>("[AHCI]");
  }

  enum ATACommands: u8 {
    Identify = 0xEC,
  };

  enum struct FisType: u8 {
    RegH2D    = 0x27, // Register FIS - host to device
    RegD2H    = 0x34, // Register FIS - device to host
    DMA_ACT   = 0x39, // DMA activate FIS - device to host
    DMA_SETUP = 0x41, // DMA setup FIS - bidirectional
    DATA      = 0x46, // Data FIS - bidirectional
    BIST      = 0x58, // BIST activate FIS - bidirectional
    PIOSetup  = 0x5F, // PIO setup FIS - device to host
    Bits      = 0xA1, // Set device bits FIS - device to host
  };

  enum struct DriveType: u32 {
    SATA    = 0x00000101,
    SATAPI  = 0xEB140101,
    EncBri  = 0xC33C0101,
    PortMux = 0x96690101,
  };

  template<int startBit, int numBits>
  using Bitfield32 = flo::Bitfield<startBit, numBits, u32 volatile >;

  /*struct RegH2D {
    union {
      u32 _0 = 0;
      Bitfield32<0, 8> fisType;

      Bitfield32<8, 4> pmport;
      Bitfield32<15, 1> cswitch;

      Bitfield32<16, 8> command;
      Bitfield32<24, 8> featureLow;
    };

    union {
      u32 _1 = 0;
      Bitfield32<0, 24> lbaLow;
      Bitfield32<24, 8> device;
    };

    union {
      u32 _2 = 0;
      Bitfield32<0, 24> lbaHigh;
      Bitfield32<24, 8> featureHigh;
    };

    union {
      u32 _3 = 0;
      Bitfield32<0, 16> count;
      Bitfield32<16, 8> icc;
      Bitfield32<24, 8> control;
    };

    u32 _4 = 0;
  };

  struct RegD2H {
    union {
      u32 _0;
      Bitfield32<0, 8> fisType;

      Bitfield32<8, 4> pmport;
      Bitfield32<14, 1> interrupt;

      Bitfield32<16, 8> status;
      Bitfield32<24, 8> error;
    };

    union {
      u32 _1;
      Bitfield32<0, 24> lbaLow;
      Bitfield32<24, 8> device;
    };

    union {
      u32 _2;
      Bitfield32<0, 24> lbaHigh;
    };

    union {
      u32 _3;
      Bitfield32<0, 16> count;
    };

    u32 _4;
  };

  struct Data {
    union {
      u32 _0 = 0;
      Bitfield32<0, 8> fisType;
      Bitfield32<8, 4> pmport;
    };

    u32 data[];
  };*/

  struct Port {
    u64 commandListBase;
    u64 fisBase;
    u32 interruptStatus;
    u32 interruptEnable;
    union {
      u32 off_10;
      Bitfield32<0, 1> start;
      Bitfield32<4, 1> receiveEnable;
      Bitfield32<14, 1> receiveRunning;
      Bitfield32<15, 1> commandListRunning;
    };
    u32 _0;
    u32 taskFileData;
    DriveType signature;
    u32 sataStatus;
    u32 sataControl;
    u32 sataError;
    u32 sataActive;
    u32 commandIssue;
    u32 sataNotification;
    u32 fisSwitch;
    u32 _1[11];
    u32 vendor[4];

    void startCommandEngine() volatile {
      receiveEnable = true;
      start = true;

      while(!receiveRunning || !commandListRunning)
        flo::yield();
    }

    void stopCommandEngine() volatile {
      start = false;
      receiveEnable = false;

      while(receiveRunning || commandListRunning)
        flo::yield();
    }

    bool shouldUse() const volatile {
      // Probably a non-present drive
      if(signature == DriveType{0xFFFFFFFF})
        return false;

      return true;
    }
  };

  static_assert(sizeof(Port) == 0x80);

  struct ABAR {
    union {
      u32 off_00;
      Bitfield32<31, 1> supports64;
    };
    union {
      u32 off_04;
      Bitfield32<31, 1> AHCIEnable;
    };
    u32 interruptStatus;
    u32 portImplemented;
    union {
      u32 off_10;
      Bitfield32<0, 8> versionPatch;
      Bitfield32<8, 8> versionMinor;
      Bitfield32<16, 16> versionMajor;
    };
    u32 cccControl;
    u32 cccPorts;
    u32 enclosureManagmentLoc;
    union {
      u32 off_24;
      Bitfield32<31, 1> biosHandoffRequired;
    };
    union {
      u32 off_28;
      Bitfield32<0, 1> biosOwned;
      Bitfield32<1, 1> osOwned;
      Bitfield32<3, 1> osOwnershipChanged;
      Bitfield32<4, 1> biosBusy;
    };

    u8 off_2C[0xA0-0x2C];  // Reserved
    u8 off_A0[0x100-0xA0]; // Vendor data

    Port ports[32];

    void claim() volatile {
      if(versionMajor >= 1 && versionMinor >= 2 && biosHandoffRequired) {
        osOwned = true;

        while(biosBusy || biosOwned || !osOwned)
          flo::yield();

        osOwnershipChanged = true;
      }
    }
  };

  static_assert(sizeof(ABAR) == 0x1100);

  struct CommandSlot {
    union {
      u32 off_0;
      Bitfield32<0, 5> fis_len;
      Bitfield32<5, 1> atapi;
      Bitfield32<6, 1> write;
      Bitfield32<7, 1> prefetchable;
      Bitfield32<8, 1> sata_reset_control;
      Bitfield32<9, 1> bist;
      Bitfield32<10, 1> clear;
      Bitfield32<12, 4> pmp;
      Bitfield32<16, 16> pdrt_count;
    };

    u32 prdbc;

    u64 command_entry_ptr;

    u8 reserved[16];
  };

  static_assert(sizeof(CommandSlot) == 32);

  struct FisSlot {
    u8 things[8];
  };

  static_assert(sizeof(FisSlot) == 8);

  struct PortMMIO {
    CommandSlot commands[32];
    static_assert(sizeof(commands) == 1024);

    FisSlot fis[32];
    static_assert(sizeof(fis) == 256);
  };

  struct AHCIDisk: Kernel::ReadWritable {
    AHCIDisk(Port volatile &port)
      : port{port}
      , mmio{
        [&]() -> volatile PortMMIO & {
          port.stopCommandEngine();

          auto [virt, phys] = flo::allocMMIO(sizeof(PortMMIO), flo::WriteBack{});
          port.commandListBase = phys() + offsetof(PortMMIO, commands);
          port.fisBase = phys() + offsetof(PortMMIO, fis);

          auto mmio = flo::getVirt<PortMMIO volatile>(virt);
          flo::Util::setmem((u8 *)mmio, 0, sizeof(*mmio));

          port.startCommandEngine();
          return *mmio;
        }()
      }
    {
      
    }

    template<typename Func>
    void sendCommand(Func &&f) {
      useCommandSlot([&](auto slot) {
        f(mmio.commands[slot], mmio.fis[slot]);
      });
    }

    template<typename Func>
    void useCommandSlot(Func &&f) {
      uSz slot = (uSz)-1;

      while(true) {
        usedCommandSlots([&](auto &commandSlots) {
          // Get a command slot
          slot = commandSlots.firstUnset();

          // Got the command slot!
          if(slot != (uSz)-1)
            commandSlots.set(slot);
        });

        // Same check, but again.
        if(slot != (uSz)-1)
          break;

        // All command slots used, let other tasks do work
        flo::yield();
      }

      f(slot);

      // Return the command slot
      usedCommandSlots([=](auto &commandSlots) {
        commandSlots.unset(slot);
      });
    }

    virtual void identify() = 0;

  private:
    Port volatile &port;
    flo::Monitored<flo::Bitset<32>> usedCommandSlots;
    void volatile *fis_areas[32];
    PortMMIO volatile &mmio;
  };

  struct SATADisk: AHCIDisk {
    SATADisk(Port volatile &port): AHCIDisk{port} { }

    void read(u8 *data, uSz size, uSz offset) override {
      assert(identified);
      //sendCommand();
      //__builtin_unreachable();
    }

    void write(u8 const *data, uSz size, uSz offset) override {
      assert(identified);
      //sendCommand();
      //__builtin_unreachable();
    }

    uSz size() override {
      assert(identified);
      return numBytes;
    }

    void identify() override {
      sendCommand([](auto &command, auto &fis) {
        flo::AHCI::pline("Command slot ", &command, " and fis ", &fis);
      });
      identified = true;
    }

  private:
    bool identified = false;
    uSz numBytes = 0;
  };

  struct SATAPIDisk: AHCIDisk {
    SATAPIDisk(volatile Port &port): AHCIDisk{port} { }

    void read(u8 *data, uSz size, uSz offset) override {
      //sendCommand();
      //__builtin_unreachable();
    }

    void write(u8 const *data, uSz size, uSz offset) override {
      //sendCommand();
      //__builtin_unreachable();
    }

    uSz size() override {
      return numBytes;
    }

    void identify() override {
      //sendCommand();
      //__builtin_unreachable();
    }

  private:
    uSz numBytes;
  };

  void portTask(volatile Port &port, int portNum) {
    flo::OwnPtr<AHCIDisk> disk;

    switch(port.signature) {
    case DriveType::SATA:
      flo::AHCI::pline("SATA drive detected on port ", portNum);
      disk = flo::OwnPtr<SATADisk>::make(port);
      break;

    case DriveType::SATAPI:
      flo::AHCI::pline("SATAPI drive detected on port ", portNum);
      disk = flo::OwnPtr<SATAPIDisk>::make(port);
      break;

    default:
      //flo::AHCI::pline("Unknown signature: ", (u32)port.signature);
      return;
    }

    disk->identify();

    Kernel::registerDisk({disk});
  }
}

void Kernel::AHCI::initialize(PCI::Reference const &ref, PCI::DeviceConfig const &device) {
  assert((device.headerType & 0x7F) == 0);

  auto abarPhys = flo::PhysicalAddress{flo::Util::get<u32>((u8 *)&device, 0x24)};
  auto abarVirt = flo::mapMMIO(abarPhys, sizeof(flo::AHCI::ABAR), flo::WriteBack{});
  auto abar = flo::getVirt<volatile flo::AHCI::ABAR>(abarVirt);

  if(!abar->supports64) {
    flo::AHCI::pline("Controller does not support 64 bit, ignoring controller");
    return;
  }

  abar->AHCIEnable = true;

  auto taskFunc = flo::TaskFunc::make<flo::Allocator>(
    [=](flo::TaskControlBlock &task) {
      abar->claim();

      flo::AHCI::pline("Claimed controller");

      auto probePort = [&](int portNum) {
        if(!abar->ports[portNum].shouldUse())
          return;

        auto portFunc = [&port = abar->ports[portNum], portNum](auto &) {
          flo::AHCI::portTask(port, portNum);
        };

        auto portTask = flo::TaskFunc::make<flo::Allocator>(flo::move(portFunc));
        flo::makeTask("AHCI port task", flo::move(portTask));
      };

      auto portImplemented = abar->portImplemented;

      for(int i = 0; i < 32; ++ i)
        if((portImplemented >> i) & 1)
          probePort(i);
    }
  );

  flo::makeTask("AHCI controller task", flo::move(taskFunc));
}
