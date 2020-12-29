#include "Kernel/Drivers/Disk/IDE.hpp"

#include "flo/IO.hpp"

namespace Kernel::IDE {
  namespace {
    constexpr bool quiet = false;
    auto pline = flo::makePline<quiet>("[IDE]");
  }
}

void Kernel::IDE::initialize(Kernel::PCI::Reference const &ref, Kernel::PCI::DeviceConfig const &device) {
  //Kernel::IDE::pline("Got IDE device");
}
