#pragma once

#include "flo/StrongTypedef.hpp"

namespace flo {
  struct VirtualAddress: flo::StrongTypedef<VirtualAddress, u64> {
    using flo::StrongTypedef<VirtualAddress, u64>::StrongTypedef;
  };

  struct PhysicalAddress: flo::StrongTypedef<PhysicalAddress, u64> {
    using flo::StrongTypedef<PhysicalAddress, u64>::StrongTypedef;
  };

  extern u8 *getPtrVirt(VirtualAddress);
  extern u8 *getPtrPhys(PhysicalAddress);
  extern PhysicalAddress getPhysicalPage();

  template<typename T>
  T *getPhys(PhysicalAddress addr) { return reinterpret_cast<T *>(getPtrPhys(addr)); }
  template<typename T>
  T *getVirt(VirtualAddress addr)  { return reinterpret_cast<T *>(getPtrVirt(addr)); }

  template<typename T>
  struct Decimal { T val; };
  template<typename T>
  Decimal(T) -> Decimal<T>;
}