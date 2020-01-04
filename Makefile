all: out/Disk.bin

ifndef QEMUExec
QEMUExec := qemu-system-x86_64
endif

ifndef QEMUFlags
QEMUFlags := -m 8G -enable-kvm -cpu host -serial stdio
endif

QEMU := $(QEMUExec) $(QEMUFlags)

CXXFlags := $(CXXFlags) -ffreestanding -g -Wall -fno-stack-protector\
	-mno-red-zone -fno-exceptions -fno-rtti -Wno-sign-compare\
	-std=c++17 -Os -mno-soft-float -Iinclude -ffunction-sections\
	-fdata-sections

CommonHeaders := $(wildcard include/**/*.hpp)

.PHONY: clean all dbg bochs test
.SECONDARY:;

TestSources := $(wildcard Tests/*.?pp)

Tests/build/CMakeCache.txt: Tests/CMakeLists.txt $(TestSources) $(CommonHeaders) Makefile
	@#rm -rfv $(@D)/CMake*
	@mkdir -p $(@D)
	cd $(@D) && cmake ..

%.stripped.elf: %.elf
	strip $< -s -o $@

# Phony targets
clean:
	@rm -rfv build out Tests/build/CMake*

dbg: out/Disk.bin
	$(QEMU) -drive format=raw,file=$< -S -s &
	gdb\
		-ex 'shell sleep .2'\
		-ex 'target remote :1234'\
		-ex 'add-symbol-file-auto build/Bootstrapper/Bootstrapper.elf'\
		-ex 'set architecture i386'\
		-ex 'set disassembly-flavor intel'\
		|| \$(killall $(QEMUExec) && false)
	killall $(QEMUExec)

kvm: out/Disk.bin
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

build/Bootsector/Bootsector.bin: build/Bootsector/Bootsector.elf
	@mkdir -p $(@D)
	objcopy -O binary $< $@

# Bootstrapper
BootstrapperSources := $(wildcard Bootstrapper/*.S) $(wildcard Bootstrapper/*.cpp)
BootstrapperObjects := $(patsubst %,build/%.o,$(BootstrapperSources))
BootstrapperHeaders := $(wildcard Bootstrapper/*.hpp)

build/Bootstrapper/%.S.o: Bootstrapper/%.S Makefile
	@mkdir -p $(@D)
	as $< -o $@ -32

build/Bootstrapper/%.cpp.o: Bootstrapper/%.cpp $(BootstrapperHeaders) $(CommonHeaders) Makefile
	@mkdir -p $(@D)
	g++ -m32 -fno-pic -fno-pie -march=i386 $(CXXFlags) -fno-use-cxa-atexit -IBootstrapper -c $< -o $@

build/Bootstrapper/Bootstrapper.elf: Bootstrapper/Linker.lds $(BootstrapperObjects)
	ld -T $^ -o $@ --gc-sections
	@readelf -a $@ | grep 'BootstrapSize' | awk '{ print "Bootstrapper size: " strtonum("0x" $$2)/(64*1024) * 100 "%" }'

build/Bootstrapper/Bootstrapper.bin: build/Bootstrapper/Bootstrapper.stripped.elf
	@mkdir -p $(@D)
	objcopy -O binary $< $@

# Literally just concat them lol
out/Disk.bin: build/Bootsector/Bootsector.bin build/Bootstrapper/Bootstrapper.bin
	@mkdir -p $(@D)
	cat $^ > $@
