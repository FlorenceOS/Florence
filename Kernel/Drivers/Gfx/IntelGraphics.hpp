#pragma once

#include "Kernel/PCI.hpp"

namespace Kernel::IntelGraphics {
  void initialize(PCI::Reference const &ref, PCI::DeviceConfig const &device);
}
