#include "Kernel/APIC.hpp"

#include "flo/Assert.hpp"
#include "flo/CPU.hpp"
#include "flo/IO.hpp"
#include "flo/Memory.hpp"

#include "flo/Containers/Bitset.hpp"

namespace Kernel::APIC {
  namespace {
    constexpr bool quiet = false;
    auto pline = flo::makePline<quiet>("[APIC]");

    void volatile *lapic;
    bool has_x2APIC() {
      return !lapic;
    }
    flo::Bitset<256> should_boot;

    uptr lapic_reg;

    u32 volatile *lapic_ptr(u32 offset) {
      assert(!has_x2APIC());
      return reinterpret_cast<u32 volatile *>(
        reinterpret_cast<u8 volatile *>(lapic) + offset
      );
    }

    void write_apic(u32 offset, u32 value) {
      if(has_x2APIC()) {
        flo::CPU::write_msr<u32>(0x800 + (offset >> 4), value);
      } else {
        *lapic_ptr(offset) = value;
      }
    }

    u32 read_apic(u32 offset) {
      if(has_x2APIC()) {
        return flo::CPU::read_msr<u32>(0x800 + (offset >> 4));
      } else {
        return *lapic_ptr(offset);
      }
    }

    void send_ipi(u32 ap_id, u32 ipi) {
      if(has_x2APIC()) {
        flo::CPU::write_msr<u64>(0x830, ((u64)ap_id << 32) | ipi);
      } else {
        write_apic(0x310, ap_id << 24);
        write_apic(0x300, ipi);
      }
    }

    u32 get_ap_id() {
      if(has_x2APIC()) {
        return read_apic(0x20);
      } else {
        return (read_apic(0x20) >> 24) & 0xFF;
      }
    }

    void boot_ap(u32 ap_id) {
      if(should_boot[ap_id]) {
        Kernel::APIC::pline("Booting AP ", ap_id);
        send_ipi(ap_id, 0x00000600);
        send_ipi(ap_id, 0x00000500);
      }
    }

    void boot_children() {
      auto id = get_ap_id();
      boot_ap(id * 2 + 1);
      boot_ap(id * 2 + 2);
    }

    struct MADT {
      u8 signature[4];
      u32 length;
      u8 revision;
      u8 checksum;
      u8 oem_id[6];
      u8 oem_table_id[0x8];
      u32 oem_rev;
      u32 creator_id;
      u32 creator_revision;
      u32 lapic_addr;
      u32 flags;
      u8 extra_bytes[];
    };

    static_assert(offsetof(MADT, extra_bytes) == 0x2C);
  }
}

extern "C" u8 ap_boot_start[];
extern "C" u8 ap_boot_end[];
extern "C" void ap_boot_store_current();

void Kernel::APIC::initialize(void const *_madt) {
  auto madt = reinterpret_cast<MADT const *>(_madt);
  if(flo::cpuid.x2apic) {
    Kernel::APIC::pline("Has x2APIC");

    lapic_reg = flo::CPU::IA32_APIC_BASE;
    lapic_reg |= 0x800; // Enable
    lapic_reg |= 0x400; // Enable x2APIC
    flo::CPU::IA32_APIC_BASE = lapic_reg;
  }
  else {
    Kernel::APIC::pline("No x2APIC");
    uptr lapic_reg = flo::CPU::IA32_APIC_BASE;
    assert(lapic_reg & 0x100); // Is a BSP

    flo::PhysicalAddress lapic_addr{lapic_reg & ~0xFFFull};

    lapic_reg |= 0x800; // Enable
    flo::CPU::IA32_APIC_BASE = lapic_reg;

    Kernel::APIC::pline("LAPIC at ", lapic_addr, "!");
    auto lapic_virt = flo::mapMMIO(lapic_addr, 0x1000, flo::WriteBack{});
    lapic = flo::getVirt<volatile void>(lapic_virt);
    assert(lapic);
    Kernel::APIC::pline("Mapped LAPIC at ", lapic);
  }

  // Enable the LAPIC
  write_apic(0xF0, 0x1FF);

  // Find out about other APs present in the system by parsing the MADT
  {
    auto const madt_limit = (u8 *)madt + madt->length;
    for(auto data = madt->extra_bytes; data + 1 < madt_limit && data + data[1] < madt_limit; data += data[1]) {
      switch(data[0]) {
      case 0:
        // AP!
        if(data[4] & 1 || data[4] & 2)
          should_boot.set(data[3]);
        break;

      case 1:
        Kernel::APIC::pline("TODO: IOAPIC");
        break;

      case 2:
        Kernel::APIC::pline("TODO: Interrupt source override");
        break;

      default:
        assert_not_reached();
        break;
      }
    }
  }

  // Otherwise this startup code doesn't do what we want, this assumes the BSP == 0
  // And that the range of CPU ids to be started is contigous and starts at 0
  assert(Kernel::APIC::get_ap_id() == 0);

  if(should_boot[1] || should_boot[2]) {
    assert(ap_boot_end - ap_boot_start < 0x1000);

    ap_boot_store_current();

    Kernel::APIC::pline(ap_boot_end - ap_boot_start, " bytes of ap boot code");

    for(auto offset = 0; offset < ap_boot_end - ap_boot_start; ++ offset)
      flo::getPhys<u8>(flo::PhysicalAddress{0})[offset] = ap_boot_start[offset];

    // Copy our page tables to 0x1000
    auto const tramp_cr3 = flo::PhysicalAddress{0x1000};
    for(auto offset = 0; offset < 0x1000; ++ offset)
      flo::getPhys<u8>(tramp_cr3)[offset] = flo::getPhys<u8>(flo::CPU::cr3)[offset];

    // Map trampoline RX
    flo::Paging::map_phys({
      .phys = flo::PhysicalAddress{0},
      .virt = flo::VirtualAddress{0},
      .size = 0x1000,
      .perm = {
        .readable = 1,
        .writeable = 0,
        .executable = 1,
        .userspace = 0,
        .cacheable = 1,
        .writethrough = 1,
        .global = 1,
      },
      .root = tramp_cr3,
    });

    boot_children();

    flo::CPU::hang();
  } else {
    Kernel::APIC::pline("No more APs to boot (single core system, how plain)");
  }
}

// Booted APs appear here
extern "C"
void booted_ap() {
  flo::CPU::IA32_APIC_BASE = Kernel::APIC::lapic_reg;

  auto id = Kernel::APIC::get_ap_id();
  Kernel::APIC::pline("Hello world from AP ", id);

  Kernel::APIC::boot_children();
}
