#include "flo/Mutex.hpp"

#include "Testing.hpp"

#include <thread>

TEST(Mutex, LockAndUnlock) {
  flo::Mutex m;
  m.lock();
  m.unlock();
}

TEST(Mutex, MutualExclusion) {
  volatile u64 a = 0;
  flo::Mutex m;

  constexpr auto numIterations = 10000;

  auto thread = [&]() {
    for(u64 i = 0; i < numIterations; ++ i) {
      m.lock();
      volatile u64 temp = a;
      a = temp + 1;
      m.unlock();
    }
  };

  constexpr auto numThreads = 10;

  std::vector<std::thread> threads;
  for(int i = 0; i < numThreads; ++ i)
    threads.emplace_back(thread);

  for(auto &t: threads)
    t.join();

  EXPECT_EQ(a, numThreads * numIterations);
}
