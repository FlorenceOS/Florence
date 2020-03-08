#include "flo/PCI.hpp"

#include "flo/Assert.hpp"
#include "flo/Bitfields.hpp"
#include "flo/IO.hpp"

namespace flo::PCI {
  namespace {
    constexpr bool quiet = true;
    auto pline = flo::makePline<quiet>("[PCI]");

    auto noVid = flo::PCI::Vid{0xFFFF};

    void request(Reference const &devRef, u8 offset) {
      union ReadPacket {
        u32 rep = 0;
        flo::Bitfield<0,  8, u32> offset;
        flo::Bitfield<8,  3, u32> function;
        flo::Bitfield<11, 5, u32> slot;
        flo::Bitfield<16, 8, u32> bus;
        flo::Bitfield<31, 1, u32> enable;
      };

      ReadPacket packet;
      packet.bus = devRef.bus();
      packet.slot = devRef.slot();
      packet.function = devRef.function();
      packet.offset = offset;
      packet.enable = 1;

      flo::IO::out<0xCF8>(packet.rep);
    }

    Vid getVendor(Reference const &devRef) {
      return Vid{read<u16>(devRef, 0)};
    }

    Pid getProduct(Reference const &devRef) {
      return Pid{read<u16>(devRef, 2)};
    }

    u8 getHeaderType(Reference const &devRef) {
      return read<u8>(devRef, 14);
    }

    DeviceClass getClass(Reference const &devRef) {
      return DeviceClass{read<u8>(devRef, 11)};
    }

    DeviceSubclass getSubclass(Reference const &devRef) {
      return DeviceSubclass{read<u8>(devRef, 10)};
    }

    Bus getSecondaryBus(Reference const &devRef) {
      return Bus{read<u8>(devRef, 0x19)};
    }

    void deviceHandler(Reference const &devRef);

    void busScan(Bus bus);

    void functionScan(Reference const &devRef) {
      auto vendor = getVendor(devRef);

      if(vendor == noVid)
        return;

      deviceHandler(devRef);

      auto deviceClass = getClass(devRef);
      if(deviceClass() == 0x06) {
        auto deviceSubclass = getSubclass(devRef);
        if(deviceSubclass() == 0x04) {
          auto b = getSecondaryBus(devRef);
          pline("PCI bridge at ", devRef.bus(), ":", devRef.slot(), ".", devRef.function(), " to bus ", b(), "!");
          busScan(b);
        }
        else {
          pline("Device function is a PCI bridge, but not a PCI to PCI bridge.");
        }
      }
      else {
        pline("Device is not a PCI bridge.");
      }
    }

    void slotScan(Bus bus, Slot slot) {
      Reference ref{bus, slot, DeviceFunction{0}};

      auto vid = getVendor(ref);
      if(vid == noVid)
        return;

      functionScan(ref);

      if(getHeaderType(ref) & 0x80) {
        for(u8 func = 1; func < 8; ++ func) {
          functionScan(Reference{bus, slot, DeviceFunction{func}});
        }
      }
      else {
        pline("Device is not a multifunction device, no more functions to scan.");
      }
    }

    void busScan(Bus bus) {
      pline("Scanning bus ", bus());
      for(u8 slot = 0; slot < 32; ++ slot)
        slotScan(bus, Slot{slot});
    }

    void deviceHandler(Reference const &dev) {
      auto ident = getDeviceIdentifier(dev);
      pline(dev.bus(), ":", dev.slot(), ".", dev.function(), ": PCI device, ",
        ident.vid(), ":", ident.pid(), " is ", ident.deviceClass(), ":", ident.deviceSubclass());

      switch(ident.deviceClass()) {
      case 0x03: // Display controller
        switch(ident.deviceSubclass()) {
        default:
          pline("Unhandled display controller subclass: ", ident.deviceSubclass());
          break;
        }
      break;

      default:
        pline("Unhandled device class ", ident.deviceClass());
        break;
      }
    }
  }
}

void flo::PCI::initialize() {
  flo::PCI::busScan(flo::PCI::Bus{0});
}

flo::PCI::Identifier flo::PCI::getDeviceIdentifier(flo::PCI::Reference const &ref) {
  Identifier ident;
  ident.vid = getVendor(ref);
  ident.pid = getProduct(ref);
  ident.deviceClass = getClass(ref);
  ident.deviceSubclass = getSubclass(ref);

  return ident;
}

template<typename T>
T flo::PCI::read(Reference const &devRef, u8 offset) {
  assert_err(offset % sizeof(T) == 0, "Misaligned PCI read!");
  request(devRef, offset);
  return flo::IO::in<T>(0xCFC + offset % 4);
}

template u8  flo::PCI::read<u8> (Reference const &devRef, u8 offset);
template u16 flo::PCI::read<u16>(Reference const &devRef, u8 offset);
template u32 flo::PCI::read<u32>(Reference const &devRef, u8 offset);

template<>
u64 flo::PCI::read<u64>(Reference const &devRef, u8 offset) {
  return (u64)flo::PCI::read<u32>(devRef, offset) | ((u64)flo::PCI::read<u32>(devRef, offset + sizeof(u32)) << 32);
}
