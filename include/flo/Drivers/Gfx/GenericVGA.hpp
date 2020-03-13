#pragma once

#include "flo/PCI.hpp"

namespace flo::GenericVGA {
  void initialize(PCI::Reference const &ref, PCI::Identifier const &ident);
}
