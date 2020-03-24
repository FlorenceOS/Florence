#pragma once

#include "flo/PCI.hpp"

namespace flo::IDE {
  void initialize(PCI::Reference const &ref, PCI::DeviceConfig const &device);
}
