#pragma once

#include "Ints.hpp"
#include "flo/Paging.hpp"
#include "flo/Containers/StaticVector.hpp"

struct MemoryRange {
  flo::PhysicalAddress begin;
  flo::PhysicalAddress end;
};

// A static vector since we don't have an allocator when this is created
extern flo::StaticVector<MemoryRange, 0x10> highMemRanges;

// Head of physical page freelist
extern flo::PhysicalAddress physicalFreeList;

// Base virtual address of physical memory
extern flo::VirtualAddress physicalVirtBase;
