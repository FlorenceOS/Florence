#include "Kernel/Drivers/Gfx/IntelGraphics.hpp"

#include "flo/IO.hpp"

namespace Kernel::IntelGraphics {
  namespace {
    constexpr bool quiet = false;
    auto pline = flo::makePline<quiet>("[IntelGFX]");
  }
}

void Kernel::IntelGraphics::initialize(PCI::Reference const &ref, PCI::DeviceConfig const &device) {
  Kernel::IntelGraphics::pline("Got Intel VGA!");
}
