#pragma once

#include "Ints.hpp"

#include "flo/Florence.hpp"

namespace flo::BIOS {
  struct MemmapEntry {
    flo::PhysicalAddress base;
    flo::PhysicalAddress size;

    enum struct RegionType: u32 {
      Usable = 1,
      Reserved = 2,
      ACPIReclaimable = 3,
      ACPINonReclaimable = 4,
      Bad = 5,
    } type;

    enum ExtendedAttribs : u32 {
      Ignore = 1,
      NonVolatile = 2,
    };

    u32 attribs;

    u32 savedEbx;
    u16 bytesFetched;
  };

  inline const char *int0x13err(u8 errc) {
    switch(errc) {
    case 0x00: return nullptr;
    case 0x01: return "Invalid Command";
    case 0x02: return "Cannot find address mark";
    default:   return "Unknown error";
    }
  }

  struct DAP {
    u8  dapSize;
    u8  reserved;
    u16 sectorsToRead;
    u16 destOffset;
    u16 destSegment;
    u64 sectorToRead;
  } __attribute__((packed));
}