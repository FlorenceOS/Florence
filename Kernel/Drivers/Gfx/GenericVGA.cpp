#include "Kernel/Drivers/Gfx/GenericVGA.hpp"

#include "flo/Assert.hpp"
#include "flo/Util.hpp"

#include "Kernel/IO.hpp"
#include "Kernel/Display.hpp"

namespace Kernel::GenericVGA {
  namespace {
    constexpr bool quiet = false;
    auto pline = flo::makePline<quiet>("[GVGA]");

    bool initialized = false;
    bool text_mode_ready = true;

    struct VGARegs {
      static constexpr u16 miscWrite = 0x3C2;
      static constexpr u16 miscRead  = 0x3CC;

      static constexpr u16 seqIndex = 0x3C4;
      static constexpr u16 seqData  = 0x3C5;

      static constexpr u16 crtcIndex = 0x3D4;
      static constexpr u16 crtcData  = 0x3D5;

      static constexpr u16 gcIndex = 0x3CE;
      static constexpr u16 gcData  = 0x3CF;

      static constexpr u16 acIndex = 0x3C0;
      static constexpr u16 acRead  = 0x3C0;
      static constexpr u16 acWrite = 0x3C1;

      static constexpr u16 vgaInstantRead = 0x3DA;

      flo::Array<u8, 01>  misc;
      flo::Array<u8, 05>  seq;
      flo::Array<u8, 031> crtc;
      flo::Array<u8, 011> gc;
      flo::Array<u8, 025> ac;

      void loadCurrent() {
        misc[0] = Kernel::IO::in<u8, miscRead>();

        for(int i = 0; i < seq.size(); ++ i) {
          Kernel::IO::out<seqIndex, u8>(i);
          seq[i] = Kernel::IO::in<u8, seqData>();
        }

        for(int i = 0; i < crtc.size(); ++ i) {
          Kernel::IO::out<crtcIndex, u8>(i);
          crtc[i] = Kernel::IO::in<u8, crtcData>();
        }

        for(int i = 0; i < gc.size(); ++ i) {
          Kernel::IO::out<gcIndex, u8>(i);
          gc[i] = Kernel::IO::in<u8, gcData>();
        }

        for(int i = 0; i < ac.size(); ++ i) {
          (void)Kernel::IO::in<u8, vgaInstantRead>();
          Kernel::IO::out<acIndex, u8>(i);
          ac[i] = Kernel::IO::in<u8, acRead>();
        }

        (void)Kernel::IO::in<u8, vgaInstantRead>();
        Kernel::IO::out<acIndex, u8>(0x20);
      }

      void unlock() {
        crtc[0x03] |= 0x80;
        crtc[0x11] &= ~0x80;
      }

      void disableTextCursor() {
        crtc[0x0A] = 0x20;
      }

      void apply() const {
        Kernel::IO::out<miscWrite>(misc[0]);

        for(int i = 0; i < seq.size(); ++ i) {
          Kernel::IO::out<seqIndex, u8>(i);
          Kernel::IO::out<seqData,  u8>(seq[i]);
        }

        // Unlock
        Kernel::IO::out<crtcIndex, u8>(0x03);
        Kernel::IO::out<crtcData , u8>(Kernel::IO::in<u8, crtcData>() | 0x80);

        Kernel::IO::out<crtcIndex, u8>(0x11);
        Kernel::IO::out<crtcData , u8>(Kernel::IO::in<u8, crtcData>() & ~0x80);

        for(int i = 0; i < crtc.size(); ++ i) {
          Kernel::IO::out<crtcIndex, u8>(i);
          Kernel::IO::out<crtcData,  u8>(crtc[i]);
        }

        for(int i = 0; i < gc.size(); ++ i) {
          Kernel::IO::out<gcIndex, u8>(i);
          Kernel::IO::out<gcData,  u8>(gc[i]);
        }

        for(int i = 0; i < ac.size(); ++ i) {
          (void)Kernel::IO::in<u8, vgaInstantRead>();
          Kernel::IO::out<acIndex, u8>(i);
          Kernel::IO::out<acWrite, u8>(ac[i]);
        }

        (void)Kernel::IO::in<u8, vgaInstantRead>();
        Kernel::IO::out<acIndex, u8>(0x20);
      }

      void print() const {
        flo::Util::hexdump(misc.data(), misc.size(), pline);
        flo::Util::hexdump(seq.data(), seq.size(), pline);
        flo::Util::hexdump(crtc.data(), crtc.size(), pline);
        flo::Util::hexdump(gc.data(), gc.size(), pline);
        flo::Util::hexdump(ac.data(), ac.size(), pline);
      }
    };

    constexpr VGARegs regs80x25 {
      {
        0x67,
      },
      {
        0x03, 0x00, 0x03, 0x00, 0x02,
      },
      {
        0x5F, 0x4F, 0x50, 0x82, 0x55, 0x81, 0xBF, 0x1F,
        0x00, 0x4F, 0x0D, 0x0E, 0x00, 0x00, 0x00, 0x50,
        0x9C, 0x0E, 0x8F, 0x28, 0x1F, 0x96, 0xB9, 0xA3,
        0xFF,
      },
      {
        0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x0E, 0x00,
        0xFF,
      },
      {
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x14, 0x07,
        0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F,
        0x0C, 0x00, 0x0F, 0x08, 0x00
      },
    };

    constexpr VGARegs regs90x60 {
      {
        0xE7,
      },
      {
        0x03, 0x01, 0x03, 0x00, 0x02,
      },
      {
        0x6B, 0x59, 0x5A, 0x82, 0x60, 0x8D, 0x0B, 0x3E,
        0x00, 0x47, 0x06, 0x07, 0x00, 0x00, 0x00, 0x00,
        0xEA, 0x0C, 0xDF, 0x2D, 0x08, 0xE8, 0x05, 0xA3,
        0xFF,
      },
      {
        0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x0E, 0x00,
        0xFF,
      },
      {
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x14, 0x07,
        0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F,
        0x0C, 0x00, 0x0F, 0x08, 0x00,
      },
    };

    VGARegs startupRegs;

    struct ModeOption {
      DisplayMode displayMode;
      VGARegs const *regs;
      struct Font *font;
    };

    ModeOption modes[] = {
      {
        { // Assume this is the mode we started in
          .identifier = 0,
          .pitch = 80,
          .width = 80,
          .height = 25,
          .bpp = 16,
          .type = DisplayMode::Type::Text,
          .native = true,
        },
        &startupRegs,
        nullptr,
      },
      {
        { // We also provide a 80x25 mode just in case the native one doesn't work out (darn UEFI)
          .identifier = 1,
          .pitch = 80,
          .width = 80,
          .height = 25,
          .bpp = 16,
          .type = DisplayMode::Type::Text,
          .native = false,
        },
        &regs80x25,
        nullptr,
      },
      {
        { // A 90x60 mode
          .identifier = 2,
          .pitch = 90,
          .width = 90,
          .height = 60,
          .bpp = 16,
          .type = DisplayMode::Type::Text,
          .native = false,
        },
        &regs90x60,
        nullptr,
      },
    };

    struct VGADisplay: Kernel::DisplayDevice {
      DisplayMode *currentMode = &modes[0].displayMode;

      DisplayID getNumDisplays() const override {
        return 1;
      }

      DisplayMode currentDisplayMode(DisplayID displayID) const override {
        assert(displayID == 0);
        return *currentMode;
      }

      void iterateDisplayModes(DisplayID displayID, flo::Function<void(DisplayMode const &)> &modeHandler) const override {
        assert(displayID == 0);
        for(auto &m: modes)
          modeHandler(m.displayMode);
      }

      void setDisplayMode(DisplayID displayID, DisplayMode const &mode) override {
        assert(displayID == 0);
        assert(mode.identifier < flo::Util::arrSz(modes));
        currentMode = &modes[mode.identifier].displayMode;

        modes[mode.identifier].regs->apply();
        //__builtin_unreachable();
      }

      flo::PhysicalAddress getFramebuffer(DisplayID displayID) const override {
        assert(displayID == 0);
        if(currentMode->type == DisplayMode::Type::Text)
          return flo::PhysicalAddress{0xB8000};
        __builtin_unreachable();
      }

      char const *name() const override {
        return "Generic VGA display";
      }
    };
  }
}

void Kernel::GenericVGA::initialize(PCI::Reference const &ref, PCI::DeviceConfig const &device) {
  if(flo::exchange(Kernel::GenericVGA::initialized, true))
    return;

  if(!Kernel::GenericVGA::text_mode_ready)
    return;

  // Read from reg to put VGA into index state
  (void)Kernel::IO::in<u8, 0x3C0>();

  Kernel::GenericVGA::startupRegs.loadCurrent();
  Kernel::GenericVGA::startupRegs.unlock();
  Kernel::GenericVGA::startupRegs.disableTextCursor();
  //Kernel::GenericVGA::startupRegs.apply();

  Kernel::registerDisplayDevice(flo::OwnPtr<VGADisplay>::make());
}

void Kernel::GenericVGA::set_vesa_fb(flo::PhysicalAddress fb, u64 pitch, u64 width, u64 height, u64 bpp) {
  if(flo::exchange(Kernel::GenericVGA::initialized, true))
    return;

  struct VESAFB: Kernel::DisplayDevice {
    VESAFB(flo::PhysicalAddress fb, u64 pitch, u64 width, u64 height, u64 bpp)
      : fb{fb}
      , pitch{pitch}
      , width{width}
      , height{height}
      , bpp{bpp}
    { }
    DisplayID getNumDisplays() const override {
      return 1;
    }

    DisplayMode dm() const {
      return DisplayMode {
        .identifier = 0,
        .pitch = pitch,
        .width = width,
        .height = height,
        .bpp = bpp,
        .type = DisplayMode::Type::VESA,
        .native = true,
      };
    }

    DisplayMode currentDisplayMode(DisplayID displayID) const override {
      assert(displayID == 0);
      return dm();
    }

    void iterateDisplayModes(DisplayID displayID, flo::Function<void(DisplayMode const &)> &modeHandler) const override {
      assert(displayID == 0);
      modeHandler(dm());
    }

    void setDisplayMode(DisplayID displayID, DisplayMode const &mode) override {
      assert(displayID == 0);
      assert(mode.identifier == 0);
    }

    flo::PhysicalAddress getFramebuffer(DisplayID displayID) const override {
      assert(displayID == 0);
      return fb;
    }

    char const *name() const override {
      return "Generic VESA framebuffer";
    }

  private:
    flo::PhysicalAddress fb;
    u64 pitch;
    u64 width;
    u64 height;
    u64 bpp;
  };

  Kernel::registerDisplayDevice(flo::OwnPtr<VESAFB>::make(fb, pitch, width, height, bpp));
}

void Kernel::GenericVGA::set_text_mode() {
  Kernel::GenericVGA::text_mode_ready = true;
}
