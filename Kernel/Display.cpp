#include "Kernel/Display.hpp"

#include "flo/IO.hpp"

namespace Kernel::Display {
  namespace {
    constexpr bool quiet = false;
    auto pline = flo::makePline<quiet>("[DISPLAY]");
  }
}

void Kernel::registerDisplayDevice(flo::OwnPtr<DisplayDevice> &&device) {
  Kernel::Display::pline("Device ", device->name(), " has ", device->getNumDisplays(), " displays");

  for(DisplayID dispNum = 0; dispNum < device->getNumDisplays(); ++dispNum) {
    auto active = device->currentDisplayMode(dispNum).identifier;
    Kernel::Display::pline("Valid display modes for display ", dispNum, ": ");

    DisplayMode lastMode;

    auto modeHandler = flo::Function<void(DisplayMode const &)>::make<flo::Allocator>([&lastMode, active](DisplayMode const &mode) {
      Kernel::Display::pline(
        mode.identifier, ": ",
        flo::Decimal{mode.width}, "x", flo::Decimal{mode.height},
        mode.type == DisplayMode::Type::Text ? " Text mode" : " RGBA8888",
        mode.native ? " (native)" : "",
        active == mode.identifier ? " (active)" : ""
      );

      lastMode = mode;
    });

    device->iterateDisplayModes(dispNum, modeHandler);
  }
}
