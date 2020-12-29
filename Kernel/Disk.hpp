#pragma once

#include "Kernel/Device.hpp"

#include "flo/Containers/Pointers.hpp"

namespace Kernel {
  void registerDisk(flo::OwnPtr<Kernel::ReadWritable> &&disk);
}
