#pragma once

#include "Kernel/PCI.hpp"

namespace Kernel::IDE {
  void initialize(PCI::Reference const &ref, PCI::DeviceConfig const &device);
}
