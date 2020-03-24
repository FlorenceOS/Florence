#pragma once

#include "Ints.hpp"

#include "flo/StrongTypedef.hpp"

namespace flo {
  namespace PCI {
    FLO_STRONG_TYPEDEF(Bus, u8);
    FLO_STRONG_TYPEDEF(Slot, u8);
    FLO_STRONG_TYPEDEF(DeviceFunction, u8);

    struct Reference {
      Bus bus;
      Slot slot;
      DeviceFunction function;
    };

    FLO_STRONG_TYPEDEF(Vid, u16);
    FLO_STRONG_TYPEDEF(Pid, u16);
    FLO_STRONG_TYPEDEF(DeviceClass, u8);
    FLO_STRONG_TYPEDEF(DeviceSubclass, u8);
    FLO_STRONG_TYPEDEF(DeviceProgIf, u8);

    struct DeviceConfig {
      Vid vid;
      Pid pid;
      u16 command;
      u16 status;
      u8 revision;
      DeviceProgIf progIf;
      DeviceSubclass deviceSubclass;
      DeviceClass deviceClass;
      u8 cacheLineSize;
      u8 latencyTimer;
      u8 headerType;
      u8 BIST;
    };

    static_assert(sizeof(DeviceConfig) == 0x10);

    DeviceConfig *getDevice(Reference const &);

    void initialize();

    // Called by ACPI when a MCFG table is found
    void registerMMIO(void *base, u8 first, u8 last);
  }
}
