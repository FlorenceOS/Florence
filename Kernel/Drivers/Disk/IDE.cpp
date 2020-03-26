#include "flo/Drivers/Disk/IDE.hpp"

#include "flo/IO.hpp"

namespace flo::IDE {
  namespace {
    constexpr bool quiet = false;
    auto pline = flo::makePline<quiet>("[IDE]");
  }
}

void flo::IDE::initialize(PCI::Reference const &ref, PCI::DeviceConfig const &device) {
}
