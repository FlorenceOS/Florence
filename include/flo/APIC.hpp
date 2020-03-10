#pragma once

#include "Ints.hpp"

#include "flo/Containers/Optional.hpp"

#include "flo/CPU.hpp"
#include "flo/IO.hpp"

namespace flo::APIC {
  inline bool exists() { return cpuid.apic; }

  inline void setBase(flo::PhysicalAddress apic) {
    CPU::IA32_APIC_BASE_MSR = apic() | 0x800;
  }

  inline auto enable = []() {
    setBase(flo::PhysicalAddress{0xFEC00000});
    return flo::nullopt;
  }();

  inline void *getBase() {
    return flo::getPhys<void>(
      flo::PhysicalAddress{CPU::IA32_APIC_BASE_MSR & 0x0000'000F'FFFF'F000});
  }
}
