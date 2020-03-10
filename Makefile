all: out/Disk.bin

ifndef QEMUExec
QEMUExec := qemu-system-x86_64
endif

QEMU := $(QEMUExec) $(QEMUFlags) -m 4G -no-reboot -serial stdio -drive format=raw,file=out/Disk.bin
KVM := $(QEMU) -enable-kvm -cpu host

CXXFlags := $(CXXFlags) \
	-ffreestanding -g -Wall -fno-stack-protector -nostdlib\
	-fno-exceptions -nostdinc++ -nostdinc -fno-rtti -Wno-sign-compare\
	-std=c++17 -Oz -mno-soft-float -Iinclude -ffunction-sections\
	-fdata-sections -funsigned-char -mno-avx -mno-avx2 -fno-use-cxa-atexit\
	-fno-builtin -fno-unwind-tables -fuse-init-array -ILibFlo -mno-sse -mno-sse2

CXXFlagsBootstrapper := $(CXXFlags) -m32 -fno-pic -fno-pie -march=i386

CXXFlags64 := $(CXXFlags) -m64

CXXFlagsKernel := $(CXXFlags64) -fpic -fpie -fno-optimize-sibling-calls -fno-omit-frame-pointer -mno-red-zone
# Kernel loader doesn't need -mno-red-zone since it has interrupts disabled
CXXFlagsKernelLoader := $(CXXFlags64) -fno-pic -fno-pie

LDFlags := --gc-sections --no-dynamic-linker -static --build-id=none
LinkingFlags := -flto -O2 -Wl,--gc-sections,--no-dynamic-linker,--icf=all,--build-id=none -fuse-ld=lld -static -ffreestanding -nostdlib

CommonHeaders := $(wildcard include/**/*.hpp)
CommonSources := $(wildcard LibFlo/*.cpp)
LibKernelSources := $(wildcard LibKernel/*.cpp)

UserspaceCXXFlags :=\
	-Oz -Wall -Werror -nostdlib -ILibFlo -Iinclude -fno-rtti -fno-exceptions -g\
	-fdata-sections -ffunction-sections -std=c++17 -nostdinc++ -nostdinc -IUserspace/include

.PHONY: clean all dbg bochs test format
.SECONDARY:;

TestSources := $(wildcard Tests/*.?pp)

Tests/build/CMakeCache.txt: Tests/CMakeLists.txt $(TestSources) $(CommonHeaders) Makefile
	@mkdir -p $(@D)
	cd $(@D) && CXX=clang++ CC=clang cmake ..

build/%.bin: build/%.elf
	@mkdir -p $(@D)
	objcopy -O binary $< $@ -j .text

# Phony targets
clean:
	@rm -rfv build out Tests/build/CMake*

dbg: out/Disk.bin
	$(QEMU) -S -s | c++filt &
	gdb-multiarch\
		-ex 'shell sleep .2'\
		-ex 'target remote :1234'\
		-ex 'set architecture i386'\
		-ex 'add-symbol-file-auto build/Bootstrapper/Bootstrapper.elf'\
		-ex 'set disassembly-flavor intel'\
		|| \$(killall $(QEMUExec) && false)
	killall $(QEMUExec)

kvm: out/Disk.bin
	$(KVM) | c++filt

go: out/Disk.bin
	$(QEMU) | c++filt

format:
	./run-clang-format.py -r Bootstrapper KernelLoader Kernel include LibFlo Tests -e Tests/build --color always | most

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

build/Bootstrapper/Bootstrapper.cpp.o: Bootstrapper/Bootstrapper.cpp $(CommonSources) $(CommonHeaders) $(LibKernelSources) Makefile
	@mkdir -p $(@D)
	./MakeUnityBuild.py $(filter %.cpp,$^) > build/Bootstrapper/Bootstrapper.cpp
	clang++ -flto $(CXXFlagsBootstrapper) -c build/Bootstrapper/Bootstrapper.cpp -I. -o $@

build/Bootstrapper/Bootstrapper.elf: Bootstrapper/Linker.lds $(BootstrapperObjects)
	clang -Xlinker -T $^ -o $@ -m32 $(LinkingFlags)
	@readelf -a $@ | grep 'BootstrapSize' | awk '{ print "Bootstrapper size: " strtonum("0x" $$2)/0x8200 * 100 "%" }'

# Kernel loader
KernelLoaderSources := KernelLoader/KernelLoader.S KernelLoader/KernelLoader.cpp
KernelLoaderObjects := $(patsubst %,build/%.o,$(KernelLoaderSources))

build/KernelLoader/KernelLoader.S.o: KernelLoader/KernelLoader.S build/Kernel/Kernel.elf Makefile
	@mkdir -p $(@D)
	nasm -felf64 $< -o $@

build/KernelLoader/KernelLoader.cpp.o: KernelLoader/KernelLoader.cpp $(CommonSources) $(CommonHeaders) $(LibKernelSources) Makefile
	@mkdir -p $(@D)
	./MakeUnityBuild.py $(filter %.cpp,$^) > build/KernelLoader/KernelLoader.cpp
	clang++ -flto $(CXXFlagsKernelLoader) -c build/KernelLoader/KernelLoader.cpp -I. -o $@

build/KernelLoader/KernelLoader.elf: KernelLoader/Linker.lds $(KernelLoaderObjects)
	clang -Xlinker -T $^ -o $@ $(LinkingFlags)
	@readelf -a $@ | grep 'KernelLoaderSize' | awk '{ print "Kernel loader size: " strtonum("0x" $$2)/(512 * 1024 * 1024) * 100 "%" }'

KernelSources := $(wildcard Kernel/*.S) Kernel/Kernel.cpp
KernelObjects := $(patsubst %,build/%.o,$(KernelSources))

build/Kernel/%.S.o: Kernel/%.S
	@mkdir -p $(@D)
	nasm -felf64 $< -o $@

build/Kernel/Kernel.cpp.o: Kernel/Kernel.cpp $(CommonSources) $(CommonHeaders) $(LibKernelSources) Makefile
	@mkdir -p $(@D)
	./MakeUnityBuild.py $(filter %.cpp,$^) > build/Kernel/Kernel.cpp
	clang++ $(CXXFlagsKernel) -c build/Kernel/Kernel.cpp -I. -o $@

build/Kernel/Kernel.elf: Kernel/Kernel.lds $(KernelObjects)
	@mkdir -p $(@D)
	@# lld crashes here :(
	@# If/when it stops, please use the bottom one :^)
	ld -T $^ -o $@ $(LDFlags) -pie -z max-page-size=0x1000
	@#clang -flto -Xlinker -T $^ -o $@ $(LinkingFlags) -fpie -Xlinker -pie

# EFI loader
EFILoaderHeaders := $(wildcard EFILoader/*.hpp)
EFILoaderSources := $(wildcard EFILoader/*.cpp)
EFILoaderObjects := $(patsubst %,build/%.o,$(EFILoaderSources))
EFIFlags   := -target x86_64-unknown-windows
EFILink    := $(EFIFlags) $(LinkingFlags) -nostdlib -Wl,entry:efi_main,-subsystem:efi_application
EFICompile := $(EFIFlags) $(CXXFlags) -fshort-char -mno-red-zone

build/EFILoader/%.cpp.o: EFILoader/%.cpp Makefile
	mkdir -p $(@D)
	clang++ $(EFIFlags) -c -o $@ $<

build/EFILoader/%.S.o: EFILoader/%.S Makefile
	mkdir -p $(@D)
	nasm -fpe64 $< -o $@

build/EFILoader/EFILoader.elf: $(EFILoaderObjects)
	mkdir -p $(@D)
	clang++ $(EFILink) -o $@ $^

# Libuserspace
UserspaceHeaders := $(wildcard Userspace/include/**/*.hpp)
LibuserspaceSources := $(wildcard Userspace/Libuserspace/*.cpp) $(wildcard Userspace/Libuserspace/*.S) $(patsubst %,Userspace/%,$(CommonSources))
LibuserspaceObjects := $(patsubst %,build/%.o,$(LibuserspaceSources))

build/Userspace/Libuserspace/%.cpp.o: Userspace/Libuserspace/%.cpp $(CommonHeaders) $(UserspaceHeaders) Makefile
	@mkdir -p $(@D)
	clang++ $(UserspaceCXXFlags) -c $< -o $@

build/Userspace/Libuserspace/%.S.o: Userspace/Libuserspace/%.S Makefile
	@mkdir -p $(@D)
	clang $(UserspaceAsmFlags) -c $< -o $@

build/Userspace/LibFlo/%.cpp.o: LibFlo/%.cpp $(CommonHeaders) $(UserspaceHeaders) Makefile
	@mkdir -p $(@D)
	clang++ $(UserspaceCXXFlags) -c $< -o $@

build/Libuserspace.o: $(LibuserspaceObjects)
	@mkdir -p $(@D)
	ar rcs $@ $^

# Userspace applications
# WIP lol

# Literally just concat boot stages to get a disk
out/Disk.bin: build/Bootsector/Bootsector.bin build/Bootstrapper/Bootstrapper.bin build/KernelLoader/KernelLoader.bin Makefile
	@mkdir -p $(@D)
	cat $(filter %.bin,$^) > $@
