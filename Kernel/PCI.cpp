#include "flo/PCI.hpp"

#include "flo/Drivers/Disk/IDE.hpp"
#include "flo/Drivers/Disk/AHCI.hpp"
#include "flo/Drivers/Gfx/IntelGraphics.hpp"
#include "flo/Drivers/Gfx/GenericVGA.hpp"

#include "flo/Assert.hpp"
#include "flo/Bitfields.hpp"
#include "flo/IO.hpp"

namespace flo::PCI {
  namespace {
    constexpr bool quiet = true;
    auto pline = flo::makePline<quiet>("[PCI]");

    auto noVid = flo::PCI::Vid{0xFFFF};

    void *mmioBase[0x100]{};

    void deviceHandler(Reference const &devRef, DeviceConfig *device);

    void busScan(Bus bus);

    struct DeviceHeader0: DeviceConfig {
      u32 bars[6];
      u32 cardbus;
      u16 subsystemVendor;
      u16 subsystemID;
      u32 expansionRom;
      u8 capabilities;
      u8 _reserved[7];
      u8 interruptLine;
      u8 interruptPin;
      u8 minGrant;
      u8 maxLatency;
    };

    static_assert(sizeof(DeviceHeader0) == 0x40);

    struct DeviceHeader1: DeviceConfig {
      u32 bars[2];
      u8 primaryBus;
      u8 secondaryBus;
    };

    static_assert(offsetof(DeviceHeader1, secondaryBus) == 0x19);

    void functionScan(Reference const &devRef) {
      auto device = getDevice(devRef);

      assert(device);

      if(device->vid != noVid)
        deviceHandler(devRef, device);
    }

    void slotScan(Bus bus, Slot slot) {
      Reference ref{bus, slot, DeviceFunction{0}};
      auto device = getDevice(ref);

      assert(device);

      if(device->vid == noVid)
        return;

      functionScan(ref);

      if(device->headerType & 0x80) {
        for(u8 func = 1; func < 8; ++ func) {
          functionScan(Reference{bus, slot, DeviceFunction{func}});
        }
      }
    }

    void busScan(Bus bus) {
      for(u8 slot = 0; slot < 32; ++ slot)
        slotScan(bus, Slot{slot});
    }

    void deviceHandler(Reference const &ref, DeviceConfig *device) {
      auto trace = [&](auto &&...vals) {
        pline(
          ref.bus(), ":", ref.slot(), ".", ref.function(), " (",
          device->vid(), ":", device->pid(), ", ",
          device->deviceClass(), ":", device->deviceSubclass(), ".", device->progIf(), ") ",
          flo::forward<decltype(vals)>(vals)...
        );
      };

      switch(device->deviceClass()) {

      case 0x01: // Mass storage controller
        switch(device->deviceSubclass()) {

        case 0x01: // IDE controller
          flo::IDE::initialize(ref, *device);
          break;

        case 0x06: // SATA controller
          switch(device->progIf()) {

          case 0x01: // AHCI
            flo::AHCI::initialize(ref, *device);
            break;

          default:
            trace("Unhandled SATA controller: ", device->progIf());
            break;

          }
          break;

        default:
          trace("Unhandled mass storage controller: ", device->deviceSubclass());
          break;

        }
        break;

      case 0x02: // Network controller
        switch(device->deviceSubclass()) {

        case 0x00: // Ethernet controller
          trace("FIXME: Ethernet controller");
          break;

        default:
          trace("Unhandled network controller: ", device->deviceSubclass());

        }
        break;

      case 0x03: // Display controller
        switch(device->deviceSubclass()) {

        case 0x00: // VGA controller
          switch(device->vid()) {

          case 0x8086:
            flo::IntelGraphics::initialize(ref, *device);
            break;
            
          default:
            flo::GenericVGA::initialize(ref, *device);
            break;

          }
          break;

        case 0x01:
          trace("FIXME: XGA controller");
          break;

        default:
          trace("Unhandled display controller subclass: ", device->deviceSubclass());
          break;

        }
        break;

      case 0x06: // Bridge
        switch(device->deviceSubclass()) {

        case 0x00: // Host bridge, we don't care.
          break;

        case 0x04: // PCI to PCI bridge
          assert((device->headerType & 0x7F) == 1);
          busScan(Bus{((DeviceHeader1 *)device)->secondaryBus});
          break;

        default:
          trace("Unhandled bridge: ", device->deviceSubclass());
          break;

        }
        break;

      case 0x0C: // Serial bus controller
        switch(device->deviceSubclass()) {

        case 0x03: // USB controllers
          switch(device->progIf()) {

            case 0x20: // EHCI
              trace("FIXME: EHCI USB2 controller");
              break;

            case 0x30: // XHCI
              trace("FIXME: XHCI USB3 controller");
              break;

            default:
              trace("Unhandled USB controller: ", device->progIf());

          }
          break;

        default:
          trace("Unhandled serial bus controller: ", device->deviceSubclass());
          break;

        }
        break;

      default:
        trace("Unhandled device class ", device->deviceClass());
        break;

      }
    }
  }
}

void flo::PCI::initialize() {
  flo::PCI::busScan(flo::PCI::Bus{0});
}

flo::PCI::DeviceConfig *flo::PCI::getDevice(Reference const &ref) {
  if(auto base = (u8 *)mmioBase[ref.bus()]; base) {
    base += ref.slot() << 15;
    base += ref.function() << 12;
    return (DeviceConfig *)base;
  }

  assert_not_reached();
  return nullptr;
}

void flo::PCI::registerMMIO(void *base, u8 first, u8 last) {
  for(int i = 0; i <= last; ++i)
    mmioBase[i] = (u8 *)base + (i << 20);
}
