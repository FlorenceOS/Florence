#pragma once

#include "flo/Florence.hpp"

#include "Kernel/PCI.hpp"

namespace Kernel::GenericVGA {
  void set_vesa_fb(flo::PhysicalAddress fb, u64 pitch, u64 width, u64 height, u64 bpp);
  void set_text_mode();
  void initialize(PCI::Reference const &ref, PCI::DeviceConfig const &device);
}
