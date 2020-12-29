all: out/Disk.bin out/EFI.bin out/ARMLoader.bin

# Configuration
ubsan := false
debug_symbols := true

QEMUExec ?= qemu-system-x86_64
QEMU := $(QEMUExec) $(QEMUFlags) -m 4G -no-reboot -debugcon stdio -machine q35 -device qemu-xhci -smp 8 -d int
QEMUArmExec ?= qemu-system-aarch64
QEMUArm := $(QEMUArmExec) -m 4G -no-reboot -serial stdio -M virt -cpu cortex-a53
KVM := $(QEMU) -enable-kvm -cpu host

CommonCXXFlags := \
  -ffreestanding -g -Wall -fno-stack-protector -nostdlib -std=c++2a \
	-fno-exceptions -nostdinc++ -nostdinc -fno-rtti -Wno-sign-compare \
	-Oz -Iinclude -ffunction-sections -fdata-sections -funsigned-char \
	-fno-use-cxa-atexit \

# Compiler options
CXXFlags := $(CXXFlags) $(CommonCXXFlags) \
  -mno-soft-float -mno-avx -mno-avx2 \
	-fno-builtin -fno-unwind-tables -fuse-init-array -ILibFlo -mno-sse -mno-sse2\
	-DFLO_ARCH_X86_64 -target x86_64-elf

CXXFlagsArm := $(CommonCXXFlags) \
	-target aarch64-none-eabi -DFLO_ARCH_AARCH64

ASMFlagsArm := \
	-target aarch64-none-eabi

LinkingFlagsARM := \
	-flto -static -ffreestanding -nostdlib \
	-target aarch64-none-eabi -Wl,--gc-sections,--no-dynamic-linker,--build-id=none -fuse-ld=lld

CXXFlagsBootstrapper := $(CXXFlags) -m32 -fno-pic -fno-pie -march=i386

CXXFlags64 := $(CXXFlags) -m64

CXXFlagsKernel := $(CXXFlags64) -fpic -fpie -mno-red-zone -fno-omit-frame-pointer
# Kernel loader doesn't need -mno-red-zone since it has interrupts disabled
CXXFlagsKernelLoader := $(CXXFlags64) -fno-pic -fno-pie

LDFlags := --gc-sections --no-dynamic-linker -static --build-id=none
LinkingFlags := -flto -O2 -Wl,--gc-sections,--no-dynamic-linker,--icf=all,--build-id=none -fuse-ld=lld -static -ffreestanding -nostdlib

# Extra, conditional flags

# Either $(ubsan) or $(debug_symbols) enables -fno-optimize-sibling-calls
no_optimize_sibling_calls := $(if $(filter true,$(ubsan) $(debug_symbols)),true,false)

CXXFlagsKernel := $(CXXFlagsKernel)\
	$(if $(filter true,$(no_optimize_sibling_calls) $(ubsan)),-fno-optimize-sibling-calls,)\
	$(if $(filter true,$(ubsan)),-fsanitize=undefined -DFLO_UBSAN,)\
	$(if $(filter true,$(debug_symbols)),-g,)\

LinkingFlags := $(LinkingFlags)\
	$(if $(filter true,$(debug_symbols)),,-s)\

UserspaceCXXFlags :=\
	-Oz -Wall -Werror -nostdlib -ILibFlo -Iinclude -fno-rtti -fno-exceptions -g\
	-fdata-sections -ffunction-sections -std=c++17 -nostdinc++ -nostdinc -IUserspace/include\

.PHONY: clean all dbg bochs test format efi arm
.SECONDARY:;

# Common source files
CommonHeaders := $(shell find LibKernel -name "*.hpp") $(shell find include -name "*.hpp")
KernelHeaders := $(shell find Kernel -name "*.hpp") $(CommonHeaders)
CommonSources := $(shell find LibFlo -name '*.cpp') $(shell find LibKernel LibFlo -name "*.cpp")

# Phony targets
clean:
	@rm -rfv build out Tests/build/CMake*

dbg: out/Disk.bin
	$(QEMU) -drive format=raw,file=$< -S -s

kvm: out/Disk.bin
	$(KVM) -drive format=raw,file=$< | c++filt

go: out/Disk.bin
	$(QEMU) -drive format=raw,file=$< | c++filt

efi: out/EFI.bin
	$(QEMU) -hda $< \
		-drive if=pflash,format=raw,unit=0,file=/usr/share/ovmf/x64/OVMF_CODE.fd,readonly=on \
		-drive if=pflash,format=raw,unit=1,file=/usr/share/ovmf/x64/OVMF_VARS.fd \
		-net none | c++filt
kvmefi: out/EFI.bin
	$(KVM) -hda $< \
		-drive if=pflash,format=raw,unit=0,file=/usr/share/ovmf/x64/OVMF_CODE.fd,readonly=on \
		-drive if=pflash,format=raw,unit=1,file=/usr/share/ovmf/x64/OVMF_VARS.fd \
		-net none | c++filt

arm: out/ARMLoader.bin
	$(QEMUArm) \
		-drive if=pflash,format=raw,file=$<,readonly=on
dbgarm: out/ARMLoader.bin
	$(QEMUArm) \
		-drive if=pflash,format=raw,file=$<,readonly=on -S -s &
	gdb-multiarch\
		-ex 'shell sleep .5'\
		-ex 'target remote :1234'\
		-ex 'set architecture aarch64'\
		|| \$(killall $(QEMUArmExec) && false)
	killall $(QEMUArmExec)

format:
	./run-clang-format.py -r Bootstrapper KernelLoader Kernel include LibFlo Tests -e Tests/build --color always | most

# .elf to .bin conversion
build/%.bin: build/%.elf
	@mkdir -p $(@D)
	llvm-objcopy -O binary $< $@ -j .text

# Test targets
TestSources := $(wildcard Tests/*.?pp)
Tests/build/CMakeCache.txt: Tests/CMakeLists.txt $(TestSources) $(CommonHeaders) Makefile
	@mkdir -p $(@D)
	cd $(@D) && CXX=clang++ CC=clang cmake ..

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
BootstrapperObjects := $(patsubst %,build/%.o,$(BootstrapperSources))

build/Bootstrapper/Bootstrapper.S.o: Bootstrapper/Bootstrapper.S Makefile
	@mkdir -p $(@D)
	nasm -felf32 $< -o $@

build/Bootstrapper/Bootstrapper.cpp.o: Bootstrapper/Bootstrapper.cpp $(CommonSources) $(KernelHeaders) Makefile
	@mkdir -p $(@D)
	./MakeUnityBuild.py $(filter %.cpp,$^) > build/Bootstrapper/Bootstrapper.cpp
	clang++ -flto $(CXXFlagsBootstrapper) -c build/Bootstrapper/Bootstrapper.cpp -I. -Ikernel -o $@

build/Bootstrapper/Bootstrapper.elf: Bootstrapper/Linker.lds $(BootstrapperObjects)
	clang -Xlinker -T $^ -o $@ -m32 $(LinkingFlags)
	@readelf -a $@ | grep 'BootstrapSize' | awk '{ print "Bootstrapper size: " strtonum("0x" $$2)/0x8200 * 100 "%" }'

# Kernel loader
KernelLoaderSources := KernelLoader/KernelLoader.S KernelLoader/KernelLoader.cpp
KernelLoaderObjects := $(patsubst %,build/%.o,$(KernelLoaderSources))

build/KernelLoader/KernelLoader.S.o: KernelLoader/KernelLoader.S build/Kernel/Kernel.elf Makefile
	@mkdir -p $(@D)
	nasm -felf64 $< -o $@

build/KernelLoader/KernelLoader.cpp.o: KernelLoader/KernelLoader.cpp $(CommonSources) $(KernelHeaders) Makefile
	@mkdir -p $(@D)
	./MakeUnityBuild.py $(filter %.cpp,$^) > build/KernelLoader/KernelLoader.cpp
	clang++ -flto $(CXXFlagsKernelLoader) -c build/KernelLoader/KernelLoader.cpp -I. -Ikernel -o $@

build/KernelLoader/KernelLoader.elf: KernelLoader/Linker.lds $(KernelLoaderObjects)
	clang -Xlinker -T $< $(filter %.o,$^) -o $@ $(LinkingFlags)
	@readelf -a $@ | grep 'KernelLoaderSize' | awk '{ print "Kernel loader size: " strtonum("0x" $$2)/(512 * 1024 * 1024) * 100 "%" }'

# Stivale loader
StivaleSources := $(shell find Stivale -name "*.cpp") $(shell find Stivale -name "*.asm")
StivaleObjects := $(patsubst %,build/%.o,$(StivaleSources))

StivaleCXXFlags := $(CXXFlags) -fno-pic

build/Stivale/%.asm.o: Stivale/%.asm Makefile
	nasm $< -felf64 -o $@

build/Stivale/Stivale.cpp.o: Stivale/Stivale.cpp $(CommonSources) $(KernelHeaders) Makefile
	@mkdir -p $(@D)
	./MakeUnityBuild.py $(filter %.cpp,$^) > build/Stivale/Stivale.cpp
	clang++ -c build/Stivale/Stivale.cpp -o $@ $(StivaleCXXFlags) -I. -Iinclude

build/Stivale/Stivale.elf: Stivale/Stivale.lds $(StivaleObjects) Makefile
	clang -Xlinker -T $< $(filter %.o,$^) -o $@ $(LinkingFlags)

# ARM loader
ARMInatorSources := $(shell find ARMInator -name "*.cpp") $(shell find ARMInator -name "*.asm")
ARMInatorObjects := $(patsubst %,build/%.o,$(ARMInatorSources))

build/ARMInator/%.asm.o: ARMInator/%.asm Makefile
	@mkdir -p $(@D)
	clang $(ASMFlagsArm) -c $< -o $@

build/ARMInator/%.cpp.o: ARMInator/%.cpp Makefile
	@mkdir -p $(@D)
	clang $(CXXFlagsArm) -c $< -o $@

build/ARMInator/ARMInator.elf: ARMInator/ARMInator.lds $(ARMInatorObjects) Makefile
	@mkdir -p $(@D)
	clang $(LinkingFlagsARM) -Xlinker -T $< $(filter %.o,$^) -o $@

out/ARMLoader.bin: build/ARMInator/ARMInator.bin
	@mkdir -p $(@D)
	cp $< $@
	truncate $@ --size '>64M' # Another arbitrary requirement

# Kernel
KernelAsm := $(shell find Kernel -name "*.S")
KernelCpp := $(shell find Kernel -name "*.cpp")
KernelObjects := $(patsubst %,build/%.o,$(KernelAsm)) build/Kernel/Kernel.cpp.o

build/Kernel/%.S.o: Kernel/%.S
	@mkdir -p $(@D)
	nasm -felf64 -F dwarf -g $< -o $@

build/Kernel/Kernel.cpp.o: $(KernelCpp) $(CommonSources) $(KernelHeaders) Makefile
	@mkdir -p $(@D)
	./MakeUnityBuild.py $(filter %.cpp,$^) > build/Kernel/Kernel.cpp
	clang++ $(CXXFlagsKernel) -c build/Kernel/Kernel.cpp -I. -o $@

build/Kernel/Kernel.elf: Kernel/Kernel.lds $(KernelObjects) Makefile
	@mkdir -p $(@D)
	@# lld crashes here :(
	@# If/when it stops, please use the bottom one :^)
	@#ld -T $^ -o $@ $(LDFlags) -pie -z max-page-size=0x1000
	clang -flto -Xlinker -T $< $(filter %.o,$^) -o $@ $(LinkingFlags) -fpie -Xlinker -pie

# Libuserspace
UserspaceHeaders := $(shell find Userspace/include -name "*.hpp") $(CommonHeaders)
LibuserspaceSources := $(wildcard Userspace/Libuserspace/*.cpp) $(wildcard Userspace/Libuserspace/*.S) $(patsubst %,Userspace/%,$(CommonSources))
LibuserspaceObjects := $(patsubst %,build/%.o,$(LibuserspaceSources))

build/Userspace/Libuserspace/%.cpp.o: Userspace/Libuserspace/%.cpp $(UserspaceHeaders) Makefile
	@mkdir -p $(@D)
	clang++ $(UserspaceCXXFlags) -c $< -o $@

build/Userspace/Libuserspace/%.S.o: Userspace/Libuserspace/%.S Makefile
	@mkdir -p $(@D)
	clang $(UserspaceAsmFlags) -c $< -o $@

build/Userspace/LibFlo/%.cpp.o: LibFlo/%.cpp $(UserspaceHeaders) Makefile
	@mkdir -p $(@D)
	clang++ $(UserspaceCXXFlags) -c $< -o $@

build/Libuserspace.o: $(LibuserspaceObjects)
	@mkdir -p $(@D)
	ar rcs $@ $^

# Userspace applications
# WIP lol

# EFI disks are a bit different since they actually have filesystems

fatMegabytes := 2
# In sectors
fatStart := 128

fatSectors := $(shell expr $(fatMegabytes) '*' 2048)
disksectors := $(shell expr $(fatStart) + $(fatSectors))

build/EFITemplate.bin: Makefile
	@mkdir -p $(@D)
	dd if=/dev/zero of=$@ bs=512 count=$(disksectors)
	parted $@ -s -a minimal mklabel gpt
	parted $@ -s -a minimal mkpart EFI FAT16 $(fatStart)s $(fatSectors)s
	parted $@ -s -a minimal toggle 1 boot

build/EFIFS.bin: $(shell find tomatboot -name "*.*") build/Stivale/Stivale.elf build/Kernel/Kernel.elf $(TOMATBOOT) Makefile
	@mkdir -p $(@D)
	dd if=/dev/zero of=$@ bs=512 count=$(fatSectors)
	mformat -i $@ -h 32 -t 32 -n 64 -c 1
	mcopy -i $@ build/Stivale/Stivale.elf build/Kernel/Kernel.elf ::
	mkdir -p tomatboot/EFI/BOOT
	cp $(TOMATBOOT) tomatboot/EFI/BOOT/
	mcopy -si $@ tomatboot/* ::

out/EFI.bin: build/EFIFS.bin build/EFITemplate.bin Makefile
	@mkdir -p $(@D)
	cp $(word 2,$^) $@
	dd if=$< of=$@ bs=512 count=$(fatSectors) seek=$(fatStart) conv=notrunc

# Literally just concat boot stages to get a disk
out/Disk.bin: build/Bootsector/Bootsector.bin build/Bootstrapper/Bootstrapper.bin build/KernelLoader/KernelLoader.bin Makefile
	@mkdir -p $(@D)
	cat $(filter %.bin,$^) > $@
	truncate $@ --size '>512K' # Don't ask me why. Q35 requires the image to be at least 512K to boot it.
