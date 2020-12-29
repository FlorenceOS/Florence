#pragma once

#include "Ints.hpp"

namespace Kernel {
  struct Readable {
    virtual ~Readable() { }
    virtual void read(u8 *data, uSz size, uSz offset) = 0;
    virtual uSz size() = 0;
  };

  struct Writable {
    virtual ~Writable() { }
    virtual void write(u8 const *data, uSz size, uSz offset) = 0;
    virtual uSz size() = 0;
  };

  struct ReadWritable: Readable, Writable {
    virtual ~ReadWritable() { }
    virtual uSz size() override = 0;
  };
}
