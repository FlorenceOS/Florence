#include "flo/ACPI.hpp"

#include "flo/Assert.hpp"
#include "flo/IO.hpp"
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

      RSDT *rsdt() {
        assert_err(revision == 0, "RSDT aquired with and XSDT available!");
        return flo::getPhys<RSDT>(flo::PhysicalAddress{rdstAddr});
      }

      XSDT *xsdt() {
        assert_err(revision > 0, "No XSDT available!");
        return flo::getPhys<XSDT>(xsdtAddr);
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
        pline("RSDT: ", header.numEntries<4>(), " entries");
        for(uSz ind = 0; ind < header.numEntries<4>(); ++ ind)
          f(*flo::getPhys<SDTHeader>(flo::PhysicalAddress{sdts[ind]}));
        pline("RSDT: Finished listing");
      }
    };

    struct XSDT {
      RSDTHeader header;
      flo::PhysicalAddress sdts[];

      template<typename F>
      void forEachSDT(F &&f) const {
        for(uSz ind = 0; ind < header.numEntries<8>(); ++ ind)
          f(*flo::getPhys<SDTHeader>(sdts[ind]));
      }
    } __attribute__((packed));
  }
}

void flo::ACPI::initialize() {
  auto rsdptr = RSDPDesc::aquire();
  if(!rsdptr)
    return;

  flo::ACPI::pline("Got RSD PTR: ", rsdptr);

  auto sdtHandler = [&](SDTHeader const &sdt) {
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
  };

  if(rsdptr->revision > 0)
    rsdptr->xsdt()->forEachSDT(sdtHandler);
  else
    rsdptr->rsdt()->forEachSDT(sdtHandler);
}
