#include "flo/ACPI.hpp"

#include "flo/Assert.hpp"
#include "flo/IO.hpp"
#include "flo/Memory.hpp"
#include "flo/PCI.hpp"

namespace flo::ACPI {
  namespace {
    constexpr bool quiet = true;
    auto pline = flo::makePline<quiet>("[ACPI]");

    bool byteZeroChecksum(void const *base, uSz size) {
      u8 checksum = 0;
      for(uSz offset = 0; offset < size; ++ offset)
        checksum += *((u8 const *)base + offset);
      return !checksum;
    }

    constexpr u32 signature(char const (&arr)[5]) {
      u32 result = 0;
      for(int i = 0; i < 4; ++ i) {
        result <<= 8;
        result += (u8)arr[3 - i];
      }
      return result;
    }

    struct RSDT;
    struct XSDT;

    inline void *SDT = nullptr;

    struct RSDPDesc {
      char signature[8];
      u8 checksum;
      char oem[6];
      u8 revision;
      u32 rdstAddr;

      // If revision > 0:
      u32 length;
      PhysicalAddress xsdtAddr;
      u8 extendedChecksum;
      u8 reserved[3];

      RSDT *rsdt() const {
        assert_err(revision == 0, "RSDT aquired with XSDT available!");
        return reinterpret_cast<RSDT *>(SDT);
      }

      XSDT *xsdt() const {
        assert_err(revision > 0, "No XSDT available!");
        return reinterpret_cast<XSDT *>(SDT);
      }

      bool validate() const {
        if(!flo::Util::memeq(signature, "RSD PTR ", sizeof(signature)))
          return false;

        // Calculate checksum
        flo::ACPI::pline("Possible ACPI with revision ", revision);
        auto numBytes = revision > 0 ? length : 20u;
        if(!byteZeroChecksum(this, numBytes))
            return false;

        return true;
      }

      static RSDPDesc *aquire() {
        auto ptr = flo::getPhys<u16>(flo::PhysicalAddress{0x40E});
        if(*ptr % 16 == 0) {
          auto rsdpdesc = flo::getPhys<RSDPDesc>(flo::PhysicalAddress{*ptr});
          if(rsdpdesc->validate()) {
            flo::ACPI::pline("Found valid RSD PTR from EBDA");
            return rsdpdesc;
          }
        }

        for(uSz mempos = 0x000E0000; mempos <= 0x00100000; mempos += 16) {
          auto rsdpdesc = flo::getPhys<RSDPDesc>(flo::PhysicalAddress{mempos});
          if(rsdpdesc->validate()) {
            flo::ACPI::pline("Found valid RSD PTR from MBDA");
            return rsdpdesc;
          }
        }

        return nullptr;
      }
    } __attribute__ ((packed));

    struct SDTHeader {
      char signature[4];
      u32 length;
      u8 revision;
      u8 checksum;
      char oem[6];
      char oemtable[8];
      u32 oemRevision;
      u32 creatorID;
      u32 creatorRevision;
    };

    static_assert(sizeof(SDTHeader) == 36);

    struct RSDTHeader {
      SDTHeader header;

      template<uSz entrySize>
      uSz numEntries() const {
        return (header.length - sizeof(SDTHeader))/entrySize;
      }
    };

    struct RSDT {
      RSDTHeader header;
      u32 sdts[];

      template<typename F>
      void forEachSDT(F &&f) const {
        for(uSz i = 0; i < header.numEntries<4>(); ++ i)
          f(flo::getPhys<u8>(flo::PhysicalAddress{sdts[i]}));
      }
    };

    struct XSDT {
      RSDTHeader header;
      u64 sdts[];

      template<typename F>
      void forEachSDT(F &&f) const {
        for(uSz i = 0; i < header.numEntries<8>(); ++ i)
          f(flo::getPhys<u8>(flo::PhysicalAddress{sdts[i]}));
      }
    } __attribute__((packed));

    struct SDTArray {
      uptr numEntries;
      SDTHeader *sdts[];
    };

    inline SDTArray *sdtarr = nullptr;

    void prepareSDTs(RSDPDesc const *ptr) {
      flo::ACPI::pline("Preparing ACPI with RSDP at ", ptr);

      u8 const *byteArray = flo::getPhys<u8>(ptr->revision ? ptr->xsdtAddr : flo::PhysicalAddress{ptr->rdstAddr});
      auto table_bytes = flo::Util::get<u32>(byteArray, 4);
      flo::ACPI::pline("Root table: ", table_bytes, " bytes at ", byteArray);

      SDT = flo::malloc_eternal(table_bytes);

      flo::Util::copymem((u8 *)SDT, byteArray, table_bytes);
      flo::ACPI::pline("Root table copied to ", SDT);

      auto numEntries = ptr->revision ? ptr->xsdt()->header.numEntries<8>() : ptr->rsdt()->header.numEntries<4>();

      sdtarr = (SDTArray *)flo::malloc_eternal(sizeof(void *) * (numEntries + 1));
      sdtarr->numEntries = 0;

      auto copy_table = [&](u8 const *sdt) {
        auto sdt_bytes = flo::Util::get<u32>(sdt, 4);
        flo::ACPI::pline("Copying ", sdt_bytes, " bytes of sdt at ", sdt);

        sdtarr->sdts[sdtarr->numEntries] = (SDTHeader *)flo::malloc_eternal(sdt_bytes);
        flo::ACPI::pline("SDT will live at ", sdtarr->sdts[sdtarr->numEntries], " from now on.");

        flo::Util::copymem((u8 *)sdtarr->sdts[sdtarr->numEntries], sdt, sdt_bytes);
        ++sdtarr->numEntries;
      };

      if(ptr->revision)
        ptr->xsdt()->forEachSDT(copy_table);
      else
        ptr->rsdt()->forEachSDT(copy_table);
    }

    template<typename F>
    void forEachSDT(F &&f) {
      for(uptr i = 0; i < sdtarr->numEntries; ++ i)
        f(*sdtarr->sdts[i]);
    }
  }
}

void flo::ACPI::initialize() {
  auto rsdptr = RSDPDesc::aquire();
  if(!rsdptr)
    return;

  prepareSDTs(rsdptr);

  flo::ACPI::pline("Got RSD PTR: ", rsdptr);

  forEachSDT([&](SDTHeader const &sdt) {
    switch(*(u32 const *)sdt.signature) {
    case signature("FACP"):
      flo::ACPI::pline("FADT at ", &sdt);
      break;

    case signature("APIC"):
      flo::ACPI::pline("APIC at ", &sdt);
      break;

    case signature("HPET"):
      flo::ACPI::pline("HPET at ", &sdt);
      break;

    case signature("MSDM"):
      flo::ACPI::pline("Got your windows key! :^)");
      flo::Util::hexdump(&sdt, sdt.length, flo::ACPI::pline);
      break;

    default:
      flo::ACPI::pline("Unknown SDT at ", &sdt, " with signature ", sdt.signature);
      break;
    }
  });
}
