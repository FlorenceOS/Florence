#include "flo/Drivers/Disk/AHCI.hpp"

#include "flo/IO.hpp"

namespace flo::AHCI {
  namespace {
    constexpr bool quiet = false;
    auto pline = flo::makePline<quiet>("[AHCI]");
  }
}

void flo::AHCI::initialize(PCI::Reference const &ref, PCI::DeviceConfig const &device) {
  flo::AHCI::pline("Found AHCI controller");
}
