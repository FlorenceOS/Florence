#pragma once

#include "Kernel/PCI.hpp"

namespace Kernel::AHCI {
  void initialize(PCI::Reference const &ref, PCI::DeviceConfig const &device);
}
