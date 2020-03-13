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

    void initialize();

    FLO_STRONG_TYPEDEF(Vid, u16);
    FLO_STRONG_TYPEDEF(Pid, u16);
    FLO_STRONG_TYPEDEF(DeviceClass, u8);
    FLO_STRONG_TYPEDEF(DeviceSubclass, u8);
    FLO_STRONG_TYPEDEF(DeviceProgIf, u8);

    struct Identifier {
      Vid vid;
      Pid pid;
      DeviceClass deviceClass;
      DeviceSubclass deviceSubclass;
      DeviceProgIf progIf;
    };

    Identifier getDeviceIdentifier(Reference const &);

    template<typename T>
    T read(Reference const &devRef, u8 offset);

    template<typename T>
    T write(Reference const &devRef, u8 offset);
  }
}
