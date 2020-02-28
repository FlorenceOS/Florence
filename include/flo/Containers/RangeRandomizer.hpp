#pragma once

#include "flo/Containers/Sorted.hpp"
#include "flo/Containers/StaticVector.hpp"

#include "flo/Random.hpp"

namespace flo {
  template<uSz alignment>
  struct RangeRandomizer {
    constexpr void add(uptr high, uSz size) {
      if(ranges.size() < ranges.capacity())
        ranges.emplace(high, size);
    }

    template<typename BitSource>
    constexpr u64 get(uSz requestedSize, BitSource &&bitSource) {
      requestedSize = flo::Util::roundUp<alignment>(requestedSize);

      uSz possibleSlides = 0;
      for(auto &r: ranges) {
        if(r.size < requestedSize)
          break;

        r.recalc(requestedSize);

        possibleSlides += r.possibleSlides;
      }

      UniformInts<uSz> dist;

      for(auto it = ranges.begin(); it != ranges.end() && possibleSlides; ++it) {
        if(it->size < requestedSize)
          break;

        dist.set(0, possibleSlides - 1);
        if(auto rnd = dist(bitSource); rnd < it->possibleSlides) {
          // Pick this one!
          auto range = *it;
          ranges.erase(it);
          auto l = [&](Range &&r) {
            if(ranges.size() == ranges.capacity()) {
              // We don't have room for it.
              // See if it's larger than our smallest,
              // because then we can just kick the smallest one out.
              if(ranges.back().size < r.size) {
                ranges.pop_back();
                ranges.emplace(flo::move(r));
              }
              return;
            }

            // We have room so just add it
            if(ranges.size() < ranges.capacity())
              ranges.emplace(flo::move(r));
          };
          range.split(rnd * alignment, requestedSize, l, l);

          return range.base + rnd * alignment;
        }

        possibleSlides -= it->possibleSlides;
      }

      return 0;
    }

    struct Range {
      uptr base;
      uSz size;
      mutable uSz possibleSlides;

      constexpr void recalc(uSz requestedSize) const {
        possibleSlides = (size - requestedSize + alignment) / alignment;
      }

      template<typename First, typename Second>
      constexpr void split(uSz offset, uSz requestedSize, First &&f, Second &&s) const {
        if(offset)                        // There will be a part before the requested one
          flo::forward<First>(f)(Range{base, offset});
        if(offset + requestedSize < size) // There will be a part after the requested one
          flo::forward<Second>(s)(Range{base + offset + requestedSize, size - offset - requestedSize});
      }
    };

  private:
    struct RangeCompare {
      constexpr bool operator()(Range const &lhs, Range const &rhs) {
        // Common case is that we're just getting a range. That means we probably
        // should sort them by size, largest first.
        return lhs.size > rhs.size;
      }
    };

    flo::Sorted<flo::StaticVector<Range, 0x100>, RangeCompare> ranges;
  };
}
