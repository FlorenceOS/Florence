#pragma once

#include "Ints.hpp"

namespace Kernel::ACPI {
  void initialize();
  void initialize(u64 rsdp);
}
