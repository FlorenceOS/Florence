all: out/Disk.bin

ifndef QEMUExec
QEMUExec := qemu-system-i386
endif

ifndef QEMUFlags
QEMUFlags := -m 1024
endif

QEMU := $(QEMUExec) $(QEMUFlags)

.PHONY: clean all dbg go
.SECONDARY:;

# Phony targets
clean:
	rm -rf build out

dbg: out/Disk.bin
	$(QEMU) -drive format=raw,file=$< -S -s &
	gdb\
		-ex 'shell sleep .2'\
		-ex 'target remote :1234'\
		-ex 'add-symbol-file-auto build/Bootsector.elf'\
		-ex 'add-symbol-file-auto build/Bootstrapper.elf'\
		-ex 'set architecture i386'\
		-ex 'set disassembly-flavor intel'\
		-ex 'break bootstrapStart'\
		-ex 'c' || \$(killall $(QEMUExec) && false)
	killall $(QEMUExec)

go: out/Disk.bin
	$(QEMU) -drive format=raw,file=$<

kvm: out/Disk.bin
	$(QEMU) -drive format=raw,file=$< -enable-kvm -cpu host

# Bootsector
build/Bootsector.S.o: Bootsector/Bootsector.S Makefile
	@mkdir -p $(@D)
	as $< -o $@ -32 -march=i386

build/Bootsector.elf: Bootsector/Linker.lds build/Bootsector.S.o
	ld -T $^ -o $@
	@readelf -a $@ | grep 'loaderSize' | awk '{ print "MBR size: " strtonum("0x" $$2)/0x1FE * 100 "%" }'

build/Bootsector.bin: build/Bootsector.elf
	@mkdir -p $(@D)
	objcopy -O binary $< $@


# Bootstrapper
BootstrapperSources := $(wildcard Bootstrapper/*.S) $(wildcard Bootstrapper/*.cpp)
BootstrapperObjects := $(patsubst %,build/%.o,$(BootstrapperSources))

build/Bootstrapper/%.S.o: Bootstrapper/%.S Makefile
	mkdir -p $(@D)
	as $< -o $@ -32

build/Bootstrapper/%.cpp.o: Bootstrapper/%.cpp Bootstrapper/*.hpp include/*.hpp Makefile
	@mkdir -p $(@D)
	gcc -m32 -march=i386 -std=c++17 -c $< -o $@

build/Bootstrapper.elf: Bootstrapper/Linker.lds $(BootstrapperObjects)
	ld -T $^ -o $@
	@readelf -a $@ | grep 'BootstrapSize' | awk '{ print "Bootstrapper size: " strtonum("0x" $$2)/(64*1024) * 100 "%" }'

build/Bootstrapper.bin: build/Bootstrapper.elf
	@mkdir -p $(@D)
	objcopy -O binary $< $@

out/Disk.bin: build/Bootsector.bin build/Bootstrapper.bin
	@mkdir -p $(@D)
	@# Literally just concat them lol
	cat $^ > $@

