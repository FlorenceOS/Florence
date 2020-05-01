#pragma once

#include "flo/Algorithm.hpp"
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
        default: break;
        }
      }

      bool valid() const {
        switch(type) {
        case RelocType::X86_64_RELATIVE: return true;
        default: return false;
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

    bool initSymbols() {
      symbolTable = nullptr;
      bool failed = false;

      forEachSection([&](ELF64::SectionHeader const &section) {
        if(section.type == ELF64::SectionHeader::Type::strtab) {
          // If this is not the section name string table
          if(&section != &sectionHeader(header().sectionNameIndex))
            if(flo::exchange(symbolTable, &section)) // Two possible symbol STRTABs
              failed = true;
        }
      });

      return !failed;
    }

    // Also calls initSymbols
    template<typename Fail>
    void verify(Fail &&fail) {
      verify_inside_file(ELF64::foff{0}, sizeof(ELF64::Header), move(fail));

      if(!equals(header().magic, "\x7F""ELF"))
        return forward<Fail>(fail)("Invalid magic for ELF file: ",
          (u8)header().magic[0], " ", (u8)header().magic[1], " ", (u8)header().magic[2], " ", (u8)header().magic[3]);

      if(header().fileclass != ELF::ObjectClass::ELF64)
        return forward<Fail>(fail)("Unexpected class: ", flo::Decimal{static_cast<u8>(header().fileclass)});

      if(header().version != ELF::Version::Current)
        return forward<Fail>(fail)("Unexpected version: ", flo::Decimal{static_cast<u8>(header().version)});

      if(!entry())
        return forward<Fail>(fail)("No entry point found: ", header().entry());

      if(header().phentsize < sizeof(ELF64::ProgramHeader))
        return forward<Fail>(fail)("Program header size (", header().shentsize, ") too low, expected at least ", sizeof(ELF64::ProgramHeader));

      if(header().phnum < 1)
        return forward<Fail>(fail)("Expecting at least one program header!");

      verify_inside_file(header().phoff, header().phentsize * header().phnum, move(fail));

      if(header().shentsize < sizeof(ELF64::SectionHeader))
        return forward<Fail>(fail)("Section header size (", header().shentsize, ") too low, expected at least ", sizeof(ELF64::SectionHeader));

      if(header().shnum < 1)
        return forward<Fail>(fail)("Expecting at least one section header!");

      if(header().shnum < header().sectionNameIndex)
        return forward<Fail>(fail)("Invalid section name string table index");

      if(sectionHeader(header().sectionNameIndex).type != ELF64::SectionHeader::Type::strtab)
        return forward<Fail>(fail)("Section name string table is not of type strtab");

      verify_inside_file(header().shoff, header().shentsize * header().shnum, move(fail));

      forEachSection([&](ELF64::SectionHeader const &section) {
        // Nobits are zero initialized and don't have backing bytes in the image
        if(section.type != ELF64::SectionHeader::Type::nobits)
          verify_inside_file(section.offset, section.size, move(fail));

        if(section.type == ELF64::SectionHeader::Type::rela)
          // There are relocations in this section, let's take a quick look at them.
          forEachRelocation(section, [&](ELF64::RelocationEntry const &relent) {
            verify_inside_loaded(relent.address, relent.size(), move(fail));
            if(!relent.valid())
              return forward<Fail>(fail)("Invalid relocation type ", (u32)relent.type);
          });

        if(section.type == ELF64::SectionHeader::Type::rel)
          return forward<Fail>(fail)("REL section handling not implemented yet.");

        if(section.type == ELF64::SectionHeader::Type::strtab) {
          if(section.size < 1)
            return forward<Fail>(fail)("strtab section is too small to contain its required null byte!");
          if(data[section.offset() + section.size - 1] != '\0')
            return forward<Fail>(fail)("strtab section not null terminated!");
          if(data[section.offset()] != '\0')
            return forward<Fail>(fail)("strtab section doesn't start with a null char");
        }
      });

      forEachProgramHeader([&](ELF64::ProgramHeader const &phdr) {
        verify_inside_file(phdr.offset, phdr.fileSz, move(fail));
        if(phdr.memSz < phdr.fileSz)
          forward<Fail>(fail)("memSz < fileSz!!");
      });

      // Required for symbolTable below
      if(!initSymbols())
        return forward<Fail>(fail)("Could not deduce symbol name string table");

      forEachSymbol([&](auto &sym) {
        // Check symbol section
        switch(sym.sectionNum) {
        case ELF64::SectionIndex::Undef:
        case ELF64::SectionIndex::Abs:
        case ELF64::SectionIndex::Common:
          break;
        default:
          // Make sure this is a valid section number
          if(sym.sectionNum >= header().shnum)
            forward<Fail>(fail)("Symbol string table index is too large: ", sym.sectionNum);
          break;
        }

        // Symbol has a name
        if(sym.stringTableOffset) {
          if(!symbolTable)
            forward<Fail>(fail)("Symbol has name but no symbol string table was found!");

          if(symbolTable->size <= sym.stringTableOffset)
            forward<Fail>(fail)("String offset ", sym.stringTableOffset, " is too large for string table size ", symbolTable->size);
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
          break;
        default:
          break;
        }
      });
    }

    void loadAll() const {
      forEachProgramHeader([&](flo::ELF64::ProgramHeader const &header) {
        if(header.type != flo::ELF64::ProgramHeader::Type::Load)
          return;

        auto sectionBase = flo::VirtualAddress{loadOffset + header.vaddr()};
        auto sectionMemSize = flo::Paging::alignPageUp(header.memSz);
        flo::Paging::Permissions perms;
        perms.writeEnable = static_cast<bool>(header.flags & header.Flags::Writeable);
        perms.mapping.executeDisable = !static_cast<bool>(header.flags & header.Flags::Executable);
        perms.mapping.global = 0;
        perms.allowUserAccess = 0;
        perms.writethrough = 0;
        perms.disableCache = 0;

        auto err = flo::Paging::map(sectionBase, sectionMemSize, perms);
        flo::checkMappingError(err, [](auto &&...) {}, flo::CPU::halt);

        if(header.fileSz)
          flo::Util::copymem((u8 *)sectionBase(), (u8 const *)fileData(header), header.fileSz);
        if(auto set = sectionMemSize - header.fileSz; set)
          flo::Util::setmem((u8 *)sectionBase() + header.fileSz, 0, set);
      });

      applyAllRelocations();
    }

  private:
    template<typename Fail>
    void verify_inside_file(ELF64::foff off, uSz region_size, Fail &&fail) {
      if(off() + region_size <= size)
        return;

      forward<Fail>(fail)("Offset ", off(), " + size ", region_size, " = ", off() + region_size, ", not <= file size (", size, ").");
    }

    template<typename Fail>
    void verify_inside_loaded(ELF64::addr off, uSz region_size, Fail &&fail) {
      bool valid = false;
      forEachProgramHeader([&](ELF64::ProgramHeader const &ph) {
        // Begins before
        if(off() < ph.vaddr())
          return;

        // Ends after
        if(off() + region_size >= ph.vaddr() + ph.memSz)
          return;

        valid = true;
      });
      if(!valid)
        forward<Fail>(fail)("Addr ", off(), " with size ", region_size, " not inside any LOADs");
    }

    ELF64::addr entry() {
      return ELF64::addr{loadOffset + header().entry()};
    }
  };
}
