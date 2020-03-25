#pragma once

#include "flo/PCI.hpp"

namespace flo::AHCI {
  void initialize(PCI::Reference const &ref, PCI::DeviceConfig const &device);
}
