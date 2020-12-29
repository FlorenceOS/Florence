#pragma once

#include "flo/Algorithm.hpp"
#include "flo/Assert.hpp"
#include "flo/Bitfields.hpp"
#include "flo/Florence.hpp"
#include "flo/Paging.hpp"
#include "flo/TypeTraits.hpp"

namespace flo {
  namespace ELF {
    enum struct ObjectClass: u8 {
      ELF32 = 1,
      ELF64 = 2,
    };

    enum struct DataEncoding: u8 {
      LittleEndian = 1,
      BigEndian    = 2,
    };

    enum struct OSABI: u8 {
      SystemV    = 0,
      HPUX       = 1,
      Standalone = 255,
    };

    enum struct Version: u8 {
      None    = 0,
      Current = 1,
    };

    enum struct ObjectType: u16 {
      None         = 0,
      Relocatable  = 1,
      Executable   = 2,
      SharedObject = 3,
      Core         = 4,
    };
  }

  namespace ELF32 {
    struct addr: flo::StrongTypedef<addr, u32> {
      using flo::StrongTypedef<addr, u32>::StrongTypedef;
    };

    struct foff: flo::StrongTypedef<foff, u32> {
      using flo::StrongTypedef<foff, u32>::StrongTypedef;
    };

    struct Header {
      u8                magic[0x4];
      ELF::ObjectClass  fileclass;
      ELF::DataEncoding encoding;
      ELF::Version      fileversion;
      u8                padding[9];
      ELF::ObjectType   type;
      u16               machine;
      ELF::Version      version;
      addr              entry;
      foff              phoff;
      foff              shoff;
      u16               flags;
      u16               ehsize;
      u16               phentsize;
      u16               phnum;
      u16               shentsize;
      u16               shnum;
      u16               shstrndx;
    };
  }

  namespace ELF64 {
    struct addr: flo::StrongTypedef<addr, u64> {
      using flo::StrongTypedef<addr, u64>::StrongTypedef;
    };

    struct foff: flo::StrongTypedef<foff, u64> {
      using flo::StrongTypedef<foff, u64>::StrongTypedef;
    };

    enum SectionIndex: u16 {
      Undef  = 0,
      Abs    = 0xFFF1,
      Common = 0xFFF2,
    };

    struct Header {
      u8                magic[0x4];
      ELF::ObjectClass  fileclass;
      ELF::DataEncoding encoding;
      ELF::Version      fileversion;
      ELF::OSABI        osabi;
      u8                abiversion;
      u8                padding[7];
      ELF::ObjectType   type;
      u16               machine;
      ELF::Version      version;
      addr              entry;
      foff              phoff;
      foff              shoff;
      u32               flags;
      u16               ehsize;
      u16               phentsize;
      u16               phnum;
      u16               shentsize;
      u16               shnum;
      u16               sectionNameIndex;
    };

    struct ProgramHeader {
      enum struct Type: u32 {
        Null    = 0,
        Load    = 1,
        Dynamic = 2,
        Interp  = 3,
        Note    = 4,
        Shlib   = 5,
        Phdr    = 6,
      };

      enum Flags: u32 {
        Executable = 1 << 0,
        Writeable  = 1 << 1,
        Readable   = 1 << 2,
      };

      Type  type;
      Flags flags;
      foff  offset;
      addr  vaddr;
      addr  paddr;
      u64   fileSz;
      u64   memSz;
      u64   align;
    };

    struct SectionHeader {
      enum struct Type: u32 {
        null     = 0,
        progbits = 1,
        symtab   = 2,
        strtab   = 3,
        rela     = 4,
        hash     = 5,
        dynamic  = 6,
        note     = 7,
        nobits   = 8,
        rel      = 9,
        dynsym   = 11,
      };

      enum Flags: u32 {
        Write = 1 << 0,
        Alloc = 1 << 1,
        Code  = 1 << 2,
      };

      u32   name;
      Type  type;
      Flags flags;
      addr  baseAddr;
      foff  offset;
      u64   size;
      u32   link;
      u32   info;
      u64   alignment;
      u64   entsize;
    };

    struct RelocationEntry {
      enum RelocType {
        X86_64_RELATIVE = 8,
      };

      addr address;
      union {
        u64 info;
        Bitfield<0, 32> type;
        Bitfield<32, 32> symbol;
      };

      i64 addend;

      u64 size() const { return 8; }

      void apply(uSz loadOffset) const {
        auto at = (u64 *)(address() + loadOffset);
        switch(type) {
        case RelocType::X86_64_RELATIVE:
          *(at) = loadOffset + addend;
          break;

        default:
          assert_not_reached();
          break;
        }
      }
    };

    static_assert(sizeof(RelocationEntry) == 24);

    struct SymbolEntry {
      u32 stringTableOffset;

      enum struct SymbolType {
        Local  = 0,
        Global = 1,
        Weak   = 2,
      };

      enum struct BindingAttributes {
        None     = 0,
        Object   = 1,
        Function = 2,
        Section  = 3,
      };

      union {
        u8  info;
        Bitfield<0, 4, u8> symbolType;
        Bitfield<4, 4, u8> bindingAttributes;
      };

      u8  other; // Reserved
      u16 sectionNum;
      u64 address;
      u64 size;
    } __attribute__((packed));

    static_assert(sizeof(SymbolEntry) == 24);
  }

  struct ELF64Image {
    u8 const *data;
    iSz size;

    // Assumed always 4K aligned
    uSz loadOffset = 0;

    ELF64::SectionHeader const *symbolTable = nullptr;

    void initSymbols() {
      symbolTable = nullptr;

      forEachSection([&](ELF64::SectionHeader const &section) {
        if(section.type == ELF64::SectionHeader::Type::strtab) {
          // If this is not the section name string table
          if(&section != &sectionHeader(header().sectionNameIndex))
            assert(!flo::exchange(symbolTable, &section)); // Two possible symbol STRTABs
        }
      });
    }

    // Also calls initSymbols
    void verify() {
      verify_inside_file(ELF64::foff{0}, sizeof(ELF64::Header));

      assert(equals(header().magic, "\x7F""ELF"));

      assert(header().fileclass == ELF::ObjectClass::ELF64);

      assert(header().version == ELF::Version::Current);

      assert(entry());
      
      assert(header().phentsize >= sizeof(ELF64::ProgramHeader));

      assert(header().phnum > 0);

      verify_inside_file(header().phoff, header().phentsize * header().phnum);

      assert(header().shentsize >= sizeof(ELF64::SectionHeader));

      assert(header().shnum > 0);

      assert(header().sectionNameIndex < header().shnum);

      assert(sectionHeader(header().sectionNameIndex).type == ELF64::SectionHeader::Type::strtab);

      verify_inside_file(header().shoff, header().shentsize * header().shnum);

      forEachSection([&](ELF64::SectionHeader const &section) {
        // Nobits are zero initialized and don't have backing bytes in the image
        if(section.type != ELF64::SectionHeader::Type::nobits)
          verify_inside_file(section.offset, section.size);

        if(section.type == ELF64::SectionHeader::Type::rela)
          // There are relocations in this section, let's take a quick look at them.
          forEachRelocation(section, [&](ELF64::RelocationEntry const &relent) {
            verify_inside_loaded(relent.address, relent.size());
          });

        assert(section.type != ELF64::SectionHeader::Type::rel);

        if(section.type == ELF64::SectionHeader::Type::strtab) {
          assert(section.size >= 1);
          assert(data[section.offset() + section.size - 1] == '\0');
          assert(data[section.offset()] == '\0');
        }
      });

      forEachProgramHeader([&](ELF64::ProgramHeader const &phdr) {
        assert(phdr.memSz >= phdr.fileSz);
      });

      // Required for symbolTable below
      initSymbols();

      forEachSymbol([&](auto &sym) {
        // Check symbol section
        switch(sym.sectionNum) {
        case ELF64::SectionIndex::Undef:
        case ELF64::SectionIndex::Abs:
        case ELF64::SectionIndex::Common:
          break;
        default:
          // Make sure this is a valid section number
          assert(sym.sectionNum < header().shnum);
          break;
        }

        // Symbol has a name
        if(sym.stringTableOffset) {
          assert(symbolTable);
          assert(symbolTable->size > sym.stringTableOffset);
        }
      });
    }

    ELF64::Header const &header() const {
      return *reinterpret_cast<ELF64::Header const *>(data);
    }

    ELF64::SectionHeader const &sectionHeader(u64 ind) const {
      return *reinterpret_cast<ELF64::SectionHeader const *>(data + header().shoff() + header().shentsize * ind);
    }

    ELF64::ProgramHeader const &programHeader(u64 ind) const {
      return *reinterpret_cast<ELF64::ProgramHeader const *>(data + header().phoff() + header().phentsize * ind);
    }

    u8 const *fileData(ELF64::ProgramHeader const &header) const {
      return data + header.offset();
    }

    u8 const *fileData(ELF64::SectionHeader const &header) const {
      return data + header.offset();
    }

    u8 const *fileData(ELF64::foff off) const {
      return data + off();
    }

    template<typename F>
    void forEachSymbol(F &&f) const {
      forEachSection([&](ELF64::SectionHeader const &shead) {
        if(shead.type == ELF64::SectionHeader::Type::symtab)
          for(uSz off = 0; off < shead.size; off += sizeof(ELF64::SymbolEntry))
            f(*reinterpret_cast<ELF64::SymbolEntry const *>(fileData(shead) + off));
      });
    }

    char const *symbolName(ELF64::SymbolEntry const &sym) const {
      if(symbolTable && sym.stringTableOffset)
        return (char const *)fileData(*symbolTable) + sym.stringTableOffset;
      return nullptr;
    }

    auto lookupSymbol(u64 addr) const {
      addr -= loadOffset;

      ELF64::SymbolEntry const *result = nullptr, *betterThanNothing = nullptr;

      forEachSymbol([&](auto &sym) {
        if(addr < sym.address) // Not the right one
          return;

        if(addr < sym.address + sym.size) // Found, it's within this one
          result = &sym;

        if(sym.size)
          return;

        // Sometimes we can be within a symbol with size 0, as when inside assembly functions
        if(!betterThanNothing)
          betterThanNothing = &sym;

        // Let's grab the last symbol before addr
        else if(sym.address > betterThanNothing->address)
          betterThanNothing = &sym;

        // Prefer symbols with names
        else if(!betterThanNothing->stringTableOffset)
          betterThanNothing = &sym;
      });

      return result ?: betterThanNothing;
    }

    template<typename F>
    void forEachSection(F &&f) const {
      for(uSz i = 1; i < header().shnum; ++i)
        f(sectionHeader(i));
    }

    template<typename F>
    void forEachProgramHeader(F &&f) const {
      for(uSz i = 0; i < header().phnum; ++i) {
        auto &header = programHeader(i);
        if(header.type != ELF64::ProgramHeader::Type::Null && header.memSz)
          f(header);
      }
    }

    template<typename F>
    void forEachRelocation(ELF64::SectionHeader const &shead, F &&f) const {
      for(uSz off = 0; off < shead.size; off += sizeof(ELF64::RelocationEntry))
        f(*reinterpret_cast<ELF64::RelocationEntry const *>(fileData(shead) + off));
    }

    void applyAllRelocations() const {
      forEachSection([&](ELF64::SectionHeader const &header) {
        switch(header.type) {
        case ELF64::SectionHeader::Type::rela:
          forEachRelocation(header, [&](ELF64::RelocationEntry const &ent) {
            ent.apply(loadOffset);
          });
          break;
        case ELF64::SectionHeader::Type::rel:
          // Not implemented!
          assert_not_reached();
          break;

        default:
          break;
        }
      });
    }

    void loadAll() const {
      // Map everything RW- temporarily...
      forEachProgramHeader([&](flo::ELF64::ProgramHeader const &header) {
        if(header.type != flo::ELF64::ProgramHeader::Type::Load)
          return;

        auto sectionBase = flo::VirtualAddress{loadOffset + header.vaddr()};
        auto sectionMemSize = flo::Paging::align_page_up(header.memSz);
        flo::Paging::Permissions perms{
          .readable = 1,
          .writeable = 1,
          .executable = 0,
          .userspace = 0,
          .cacheable = 1,
          .writethrough = 1,
          .global = 0,
        };

        flo::Paging::map({
          .virt = sectionBase,
          .size = sectionMemSize,
          .perm = perms,
        });

        // Put the data in memory...
        if(header.fileSz)
          flo::Util::copymem((u8 *)sectionBase(), (u8 const *)fileData(header), header.fileSz);
        if(auto set = sectionMemSize - header.fileSz; set)
          flo::Util::setmem((u8 *)sectionBase() + header.fileSz, 0, set);
      });

      // The relocations ofc also have to be done while things are RW-
      applyAllRelocations();

      // Now we can set the access permissions properly.
      forEachProgramHeader([&](flo::ELF64::ProgramHeader const &header) {
        if(header.type != flo::ELF64::ProgramHeader::Type::Load)
          return;

        auto sectionBase = flo::VirtualAddress{loadOffset + header.vaddr()};
        auto sectionMemSize = flo::Paging::align_page_up(header.memSz);

        flo::Paging::Permissions perms;
        perms.writeable = static_cast<bool>(header.flags & header.Flags::Writeable);
        perms.executable = static_cast<bool>(header.flags & header.Flags::Executable);
        perms.readable = 1;
        perms.global = 0;
        perms.userspace = 0;
        perms.writethrough = 0;
        perms.cacheable = 1;

        flo::Paging::set_perms({
          .virt = sectionBase,
          .size = sectionMemSize,
          .perm = perms,
        });
      });
    }

    ELF64::addr entry() {
      return ELF64::addr{loadOffset + header().entry()};
    }

  private:
    void verify_inside_file(ELF64::foff off, uSz region_size) {
      assert(off() + region_size <= size);
    }

    void verify_inside_loaded(ELF64::addr off, uSz region_size) {
      bool valid = false;
      forEachProgramHeader([&](ELF64::ProgramHeader const &ph) {
        // Begins before
        if(off() < ph.vaddr())
          return;

        // Ends after
        if(off() + region_size > ph.vaddr() + ph.memSz)
          return;

        valid = true;
      });
      assert(valid);
    }
  };
}
