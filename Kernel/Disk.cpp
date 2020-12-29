#include "Kernel/Disk.hpp"

#include "flo/IO.hpp"

namespace Disk {
  namespace {
    constexpr bool quiet = true;
    auto pline = flo::makePline<quiet>("[DISK]");
  }
}

void Kernel::registerDisk(flo::OwnPtr<Kernel::ReadWritable> &&disk) {
  Disk::pline("Reigstered disk struct at ", disk.get(), " with size ", disk->size());
}
