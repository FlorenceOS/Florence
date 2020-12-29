#pragma once

#include "Ints.hpp"

#include "flo/Containers/Pointers.hpp"
#include "flo/Containers/Function.hpp"

namespace Kernel {
  // Depth = 4 is assumed
  struct DisplayMode {
    u64 identifier;
    u64 pitch;
    u64 width;
    u64 height;
    u64 bpp;
    enum struct Type {
      Text,
      VESA,
    };
    Type type;
    bool native;
  };

  using DisplayID = u64;

  struct DisplayDevice {
    virtual ~DisplayDevice() { }
    virtual DisplayID getNumDisplays() const = 0;
    virtual DisplayMode currentDisplayMode(DisplayID displayID) const = 0;
    virtual char const *name() const = 0;
    virtual void iterateDisplayModes(DisplayID displayID, flo::Function<void(DisplayMode const &)> &modeHandler) const = 0;
    virtual void setDisplayMode(DisplayID, DisplayMode const &mode) = 0;
    virtual flo::PhysicalAddress getFramebuffer(DisplayID) const = 0;
  };

  void registerDisplayDevice(flo::OwnPtr<DisplayDevice> &&disp);
}
