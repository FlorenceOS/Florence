#pragma once

#include "Ints.hpp"

#include "flo/Florence.hpp"

namespace flo::BIOS {
  template<typename T>
  struct RealPtr {
    u16 offset;
    u16 segment;

    T *operator()() const { return flo::getPhys<T>(PhysicalAddress(offset + (segment << 4))); }
  } __attribute__((packed));

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

  struct VesaInfo {
    char signature[4];
    u8 versionMinor, versionMajor;
    RealPtr<char> oem;
    u32 capabilities;
    RealPtr<u16> video_modes;
    u16 video_memory;
    u16 software_rev;
    RealPtr<char> vendor;
    RealPtr<char> product_name;
    RealPtr<char> product_rev;
  } __attribute__((packed));

  struct VideoMode {
    u16 attributes;
    u8  window_a;
    u8  window_b;
    u16 granularity;
    u16 window_size;
    u16 segment_a;
    u16 segment_b;
    u32 win_func_ptr;
    u16 pitch; // Bytes per line
    u16 width;
    u16 height;
    u8  w_char;
    u8  y_char;
    u8  planes;
    u8  bpp; // Bits per pixel
    u8  banks;
    u8  memory_model;
    u8  bank_size;
    u8  image_pages;
    u8  reserved0;
   
    u8  red_mask;
    u8  red_position;
    u8  green_mask;
    u8  green_position;
    u8  blue_mask;
    u8  blue_position;
    u8  reserved_mask;
    u8  reserved_position;
    u8  direct_color_attributes;
   
    u32 framebuffer;
    u32 off_screen_mem_off;
    u16 off_screen_mem_size;
  } __attribute__((packed));

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
    u8  const reserved;
    u16 sectorsToRead;
    u16 destOffset;
    u16 destSegment;
    u64 sectorToRead;
  } __attribute__((packed));
}