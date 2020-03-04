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

    template<typename T>
    T read(Reference const &devRef, u8 offset) {
      assert_err(offset % sizeof(T) == 0, "Misaligned PCI read!");
      request(devRef, offset);
      return flo::IO::in<T>(0xCFC + offset % 4);
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
      return Bus{read<u8>(devRef, 19)};
    }

    void busScan(Bus bus, Function<void(Reference const &)> const &callback);

    void functionScan(Reference const &devRef, Function<void(Reference const &)> const &callback) {
      auto vendor = getVendor(devRef);

      if(vendor == noVid)
        return;

      callback(devRef);

      auto deviceClass = getClass(devRef);
      if(deviceClass() == 0x06) {
        auto deviceSubclass = getSubclass(devRef);
        if(deviceSubclass() == 0x04) {
          pline("PCI bridge at ", devRef.bus(), ":", devRef.slot(), ".", devRef.function(), " is a PCI to PCI bridge, recursing!");
          busScan(getSecondaryBus(devRef), callback);
        }
        else {
          pline("Device function is a PCI bridge, but not a PCI to PCI bridge.");
        }
      }
      else {
        pline("Device is not a PCI bridge.");
      }
    }

    void deviceScan(Bus bus, Slot slot, Function<void(Reference const &)> const &callback) {
      Reference ref{bus, slot, DeviceFunction{0}};

      auto vid = getVendor(ref);
      if(vid == noVid)
        return;

      functionScan(ref, callback);

      if(getHeaderType(ref) & 0x80) {
        for(u8 func = 1; func < 8; ++ func) {
          functionScan(Reference{bus, slot, DeviceFunction{func}}, callback);
        }
      }
      else {
        pline("Device is not a multifunction device, no more functions to scan.");
      }
    }

    void busScan(Bus bus, Function<void(flo::PCI::Reference const &)> const &callback) {
      pline("Scanning bus ", bus());
      for(u8 slot = 0; slot < 32; ++ slot)
        deviceScan(bus, Slot{slot}, callback);
    }
  }
}

void flo::PCI::IterateDevices(flo::Function<void(flo::PCI::Reference const &)> const &callback) {
  flo::PCI::busScan(flo::PCI::Bus{0}, callback);
}

flo::PCI::Identifier flo::PCI::getDeviceIdentifier(flo::PCI::Reference const &ref) {
  Identifier ident;
  ident.vid = getVendor(ref);
  ident.pid = getProduct(ref);
  ident.deviceClass = getClass(ref);
  ident.deviceSubclass = getSubclass(ref);

  return ident;
}
