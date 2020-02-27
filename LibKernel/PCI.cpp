#include "flo/PCI.hpp"

#include "flo/Assert.hpp"
#include "flo/Bitfields.hpp"
#include "flo/IO.hpp"

namespace flo::PCI {
  namespace {
    constexpr bool quiet = true;
    auto pline = flo::makePline<quiet>("[PCI]");

    auto noVid = flo::PCI::Vid{0xFFFF};

    void request(Bus bus, Dev device, Func func, u8 offset) {
      union ReadPacket {
        u32 rep = 0;
        flo::Bitfield<0,  8, u32> offset;
        flo::Bitfield<8,  3, u32> function;
        flo::Bitfield<11, 5, u32> device;
        flo::Bitfield<16, 8, u32> bus;
        flo::Bitfield<31, 1, u32> enable;
      };

      ReadPacket packet;
      packet.bus = bus();
      packet.device = device();
      packet.function = func();
      packet.offset = offset;
      packet.enable = 1;

      flo::IO::out<0xCF8>(packet.rep);
    }

    template<typename T>
    T read(Bus bus, Dev device, Func func, u8 offset) {
      assert_err(offset % sizeof(T) == 0, "Misaligned PCI read!");
      request(bus, device, func, offset);
      return flo::IO::in<T>(0xCFC + offset % 4);
    }

    Vid getVendor(Bus bus, Dev device, Func function) {
      return Vid{read<u16>(bus, device, function, 0)};
    }

    Pid getProduct(Bus bus, Dev device, Func function) {
      return Pid{read<u16>(bus, device, function, 2)};
    }

    u8 getHeaderType(Bus bus, Dev device, Func function) {
      return read<u8>(bus, device, function, 14);
    }

    u8 getClass(Bus bus, Dev device, Func function) {
      return read<u8>(bus, device, function, 11);
    }

    u8 getSubclass(Bus bus, Dev device, Func function) {
      return read<u8>(bus, device, function, 10);
    }

    Bus getSecondaryBus(Bus bus, Dev device, Func function) {
      return Bus{read<u8>(bus, device, function, 19)};
    }

    void busScan(Bus bus, Function<void(Device const &)> const &callback);

    void functionScan(Bus bus, Dev device, Func function, Function<void(Device const &)> const &callback) {
      Device pcidev;
      pcidev.vid = getVendor(bus, device, function);

      if(pcidev.vid == noVid)
        return;

      pcidev.bus = bus;
      pcidev.dev = device;
      pcidev.pid = getProduct(bus, device, function);
      pcidev.func = function;

      callback(pcidev);

      auto deviceClass = getClass(bus, device, function);
      if(deviceClass == 0x06) {
        auto deviceSubclass = getSubclass(bus, device, function);
        if(deviceSubclass == 0x04) {
          pline("PCI bridge at ", function(), " in ", bus(), ":", device(), " is a PCI to PCI bridge, recursing!");
          busScan(getSecondaryBus(bus, device, function), callback);
        }
        else {
          pline("Device function is a PCI bridge, but not a PCI to PCI bridge.");
        }
      }
      else {
        pline("Device is not a PCI bridge.");
      }
    }

    void deviceScan(Bus bus, Dev device, Function<void(Device const &)> const &callback) {
      auto vid = getVendor(bus, device, Func{0});
      if(vid == noVid)
        return;

      functionScan(bus, device, Func{0}, callback);

      if(getHeaderType(bus, device, Func{0}) & 0x80) {
        for(u8 func = 1; func < 8; ++ func)
          functionScan(bus, device, Func{func}, callback);
      }
      else {
        pline("Device is not a multifunction device, no more functions to scan.");
      }
    }

    void busScan(Bus bus, Function<void(flo::PCI::Device const &)> const &callback) {
      pline("Scanning bus ", bus());
      for(u8 i = 0; i < 32; ++ i)
        deviceScan(bus, Dev{i}, callback);
    }
  }
}

void flo::PCI::IterateDevices(flo::Function<void(flo::PCI::Device const &)> const &callback) {
  flo::PCI::busScan(flo::PCI::Bus{0}, callback);
}
