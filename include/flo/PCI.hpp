#pragma once

#include "Ints.hpp"

#include "flo/StrongTypedef.hpp"

#include "flo/Containers/Function.hpp"

namespace flo {
  namespace PCI {
    FLO_STRONG_TYPEDEF(Vid, u16);
    FLO_STRONG_TYPEDEF(Pid, u16);
    FLO_STRONG_TYPEDEF(Bus, u8);
    FLO_STRONG_TYPEDEF(Dev, u8);
    FLO_STRONG_TYPEDEF(Func, u8);

    struct Device {
      Vid vid;
      Pid pid;
      Bus bus;
      Dev dev;
      Func func;
    };

    void IterateDevices(Function<void(Device const &)> const &);
  }
}
