#include "flo/Drivers/Gfx/IntelGraphics.hpp"

#include "flo/IO.hpp"

namespace flo::IntelGraphics {
  namespace {
    constexpr bool quiet = false;
    auto pline = flo::makePline<quiet>("[IntelGFX]");
  }
}

void flo::IntelGraphics::initialize(PCI::Reference const &ref, PCI::Identifier const &ident) {
  flo::IntelGraphics::pline("Got Intel VGA at ", ref.bus(), ":", ref.slot(), ".", ref.function());
}
