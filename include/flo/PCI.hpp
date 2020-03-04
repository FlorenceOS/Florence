#pragma once

#include "Ints.hpp"

#include "flo/StrongTypedef.hpp"

#include "flo/Containers/Function.hpp"

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

    void IterateDevices(Function<void(Reference const &)> const &);

    FLO_STRONG_TYPEDEF(Vid, u16);
    FLO_STRONG_TYPEDEF(Pid, u16);
    FLO_STRONG_TYPEDEF(DeviceClass, u8);
    FLO_STRONG_TYPEDEF(DeviceSubclass, u8);

    struct Identifier {
      Vid vid;
      Pid pid;
      DeviceClass deviceClass;
      DeviceSubclass deviceSubclass;
    };

    Identifier getDeviceIdentifier(Reference const &);
  }
}
