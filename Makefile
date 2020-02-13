all: out/Disk.bin

ifndef QEMUExec
QEMUExec := qemu-system-x86_64
endif

ifndef QEMUFlags
QEMUFlags := -serial stdio
endif

QEMU := $(QEMUExec) $(QEMUFlags) -m 1M -no-reboot
KVM := $(QEMU) -enable-kvm -cpu host

CXXFlags := $(CXXFlags) \
	-ffreestanding -g -Wall -fno-stack-protector -nostdlib\
	-fno-exceptions -nostdinc++ -nostdinc -fno-rtti -Wno-sign-compare\
	-std=c++17 -Oz -mno-soft-float -Iinclude -ffunction-sections\
	-fdata-sections -funsigned-char -mno-avx -mno-avx2 -fno-use-cxa-atexit\
  -fno-builtin -fno-unwind-tables

LDFlags := --gc-sections --no-dynamic-linker -static
LinkingFlags :=  -flto -O2 -Wl,--gc-sections,--no-dynamic-linker,--icf=all -fuse-ld=lld -static -ffreestanding -nostdlib

CommonHeaders := $(wildcard include/**/*.hpp)
LibFloSources := LibFlo/LibFlo.cpp

build/LibFlo32.o: $(LibFloSources) $(CommonHeaders) Makefile
	clang++ -m32 -fno-pic -fno-pie $(CXXFlags) -c $(filter %.cpp,$^) -o $@

build/LibFlo64.o: $(LibFloSources) $(CommonHeaders) Makefile
	clang++ -m64 -fno-pic -fno-pie $(CXXFlags) -c $(filter %.cpp,$^) -o $@

build/LibFloPIC.o: $(LibFloSources) $(CommonHeaders) Makefile
	clang++ -m64 -fpic -fpie $(CXXFlags) -c $(filter %.cpp,$^) -o $@

.PHONY: clean all dbg bochs test
.SECONDARY:;

TestSources := $(wildcard Tests/*.?pp)

Tests/build/CMakeCache.txt: Tests/CMakeLists.txt $(TestSources) $(CommonHeaders) Makefile
	@mkdir -p $(@D)
	cd $(@D) && cmake ..

build/%.bin: build/%.elf
	@mkdir -p $(@D)
	objcopy -O binary $< $@

# Phony targets
clean:
	@rm -rfv build out Tests/build/CMake*

dbg: out/Disk.bin
	$(QEMU) -drive format=raw,file=$< -S -s &
	gdb-multiarch\
		-ex 'shell sleep .2'\
		-ex 'target remote :1234'\
		-ex 'set architecture i386'\
		-ex 'add-symbol-file-auto build/Bootstrapper/Bootstrapper.elf'\
		-ex 'set disassembly-flavor intel'\
		|| \$(killall $(QEMUExec) && false)
	killall $(QEMUExec)

kvm: out/Disk.bin
	$(KVM) -drive format=raw,file=$<

go: out/Disk.bin
	$(QEMU) -drive format=raw,file=$<

test: Tests/build/CMakeCache.txt
	make -j -C Tests/build
	gdb Tests/build/tests\
		-ex 'r --gtest_break_on_failure'

autotest: Tests/build/CMakeCache.txt
	make -j -C Tests/build
	Tests/build/tests --gtest_output=xml:"tests.xml"

# Bootsector
build/Bootsector/Bootsector.S.o: Bootsector/Bootsector.S Makefile
	@mkdir -p $(@D)
	as $< -o $@ -32 -march=i386

build/Bootsector/Bootsector.elf: Bootsector/Linker.lds build/Bootsector/Bootsector.S.o
	ld -T $^ -o $@
	@readelf -a $@ | grep 'loaderSize' | awk '{ print "MBR size: " strtonum("0x" $$2)/0x1FE * 100 "%" }'

# Bootstrapper
BootstrapperSources := Bootstrapper/Bootstrapper.S Bootstrapper/Bootstrapper.cpp
BootstrapperObjects := $(patsubst %,build/%.o,$(BootstrapperSources) LibFlo32)

build/Bootstrapper/Bootstrapper.S.o: Bootstrapper/Bootstrapper.S Makefile
	@mkdir -p $(@D)
	nasm -felf32 $< -o $@

build/Bootstrapper/Bootstrapper.cpp.o: Bootstrapper/Bootstrapper.cpp $(CommonHeaders) Makefile
	@mkdir -p $(@D)
	clang++ -flto -m32 -fno-pic -fno-pie -march=i386 $(CXXFlags) -c $< -o $@

build/Bootstrapper/Bootstrapper.elf: Bootstrapper/Linker.lds $(BootstrapperObjects)
	clang -Xlinker -T $^ -o $@ -m32 $(LinkingFlags)
	@readelf -a $@ | grep 'BootstrapSize' | awk '{ print "Bootstrapper size: " strtonum("0x" $$2)/(0x10000 - 0x7E00) * 100 "%" }'

# Kernel loader
KernelLoaderSources := KernelLoader/KernelLoader.S KernelLoader/KernelLoader.cpp
KernelLoaderObjects := $(patsubst %,build/%.o,$(KernelLoaderSources) LibFlo64)

build/KernelLoader/KernelLoader.S.o: KernelLoader/KernelLoader.S build/Kernel/Kernel.elf Makefile
	@mkdir -p $(@D)
	nasm -felf64 $< -o $@

build/KernelLoader/KernelLoader.cpp.o: KernelLoader/KernelLoader.cpp $(CommonHeaders) Makefile
	@mkdir -p $(@D)
	clang++ -m64 -fno-pic -fno-pie $(CXXFlags) -c $< -o $@

build/KernelLoader/KernelLoader.elf: KernelLoader/Linker.lds $(KernelLoaderObjects)
	clang -Xlinker -T $^ -o $@ $(LinkingFlags)
	@readelf -a $@ | grep 'KernelLoaderSize' | awk '{ print "Kernel loader size: " strtonum("0x" $$2)/(512 * 1024 * 1024) * 100 "%" }'

KernelSources := $(wildcard Kernel/*.S) Kernel/Kernel.cpp
KernelObjects := $(patsubst %,build/%.o,$(KernelSources) LibFloPIC)

build/Kernel/%.S.o: Kernel/%.S
	@mkdir -p $(@D)
	nasm -felf64 $< -o $@

build/Kernel/Kernel.cpp.o: Kernel/Kernel.cpp $(CommonHeaders) Makefile
	@mkdir -p $(@D)
	clang++ -m64 -fpic -fpie $(CXXFlags) -c $< -o $@

build/Kernel/Kernel.elf: Kernel/Kernel.lds $(KernelObjects)
	@mkdir -p $(@D)
	@# lld crashes here :(
	@# If/when it stops, please use the bottom one :^)
	ld -T $^ -o $@ $(LDFlags) -pie -s
	@#clang -Xlinker -T $^ -o $@ $(LinkingFlags) -fpie -Xlinker -pie

# Literally just concat them lol
out/Disk.bin: build/Bootsector/Bootsector.bin build/Bootstrapper/Bootstrapper.bin build/KernelLoader/KernelLoader.bin Makefile
	@mkdir -p $(@D)
	cat $(filter %.bin,$^) > $@
