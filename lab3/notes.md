LAB-3: Trusted Firmware-A + U-Boot + QEMU
Complete Step-by-Step Lab Report
From initial host setup and TF-A build through successful QEMU boot to the U-Boot prompt

1. Purpose of LAB-3
LAB-3 was designed to move from the basic ARM64/QEMU work of the earlier labs into a real firmware boot-chain study. The main goal was to build Arm Trusted Firmware-A (TF-A), build U-Boot for AArch64, package U-Boot as BL33, construct a QEMU flash image, and prove that the complete chain can execute.
The lab deliberately separates two ideas: first, proving that firmware stages can execute in the expected order; second, later studying whether those stages are cryptographically authenticated. The work completed in this chat successfully demonstrated the first part. Trusted Board Boot authentication was not yet enabled.
2. High-Level Result
The final runtime chain successfully reached the U-Boot command prompt:
QEMU
  |
  v
BL1  -> TF-A
  |
  v
BL2  -> TF-A
  |
  v
BL31 -> TF-A EL3 runtime firmware
  |
  v
BL33 -> U-Boot
  |
  v
U-Boot prompt: =>
The QEMU output showed BL1 booting BL2, BL2 booting BL31, and then U-Boot starting. The automatic U-Boot bootflow later failed to find a kernel/TFTP boot image, but that did not mean the firmware chain failed. The system remained at the U-Boot shell, which was the intended checkpoint for this stage.
3. Host Environment
The environment recorded during the project was an x86-64 Ubuntu host with an AArch64 cross compiler and QEMU system emulator.
Item	Recorded value	Role
Host architecture	x86_64	Machine on which builds and QEMU run
QEMU	10.2.1	System emulator used to execute the ARM64 firmware
AArch64 GCC	15.2.0	Cross compiler for ARM64 firmware
Git	2.53.0	Source-code management
TF-A	v2.15.0-655-g0093e24ec	Trusted Firmware-A source/build
U-Boot	v2026.10-rc4, b4ac71db13a	Normal-world boot firmware / BL33
4. Workspace and Directory Structure
~/qemu/lab3/
└── src/
    ├── trusted-firmware-a/
    │   ├── build/qemu/release/
    │   │   ├── bl1.bin
    │   │   ├── bl2.bin
    │   │   ├── bl31.bin
    │   │   ├── fip.bin
    │   │   └── tools/fiptool/fiptool
    │   └── flash.bin
    │
    └── u-boot/
        ├── u-boot
        ├── u-boot.bin
        └── .config
The workspace was kept under ~/qemu/lab3/src. This matters because the BL33 path used later was ../u-boot/u-boot.bin from inside the TF-A directory.
5. Important Firmware Concepts Used in the Lab
Term	Simple meaning	Responsibility in this lab
TF-A	Arm Trusted Firmware-A	Provides early boot stages and EL3 runtime firmware
BL1	First TF-A boot stage	Acts as the first firmware stage in QEMU's emulated boot flow and locates the FIP
BL2	Second TF-A boot stage	Loads the next firmware images and prepares the boot hand-off
BL31	TF-A EL3 runtime firmware	Runs at EL3 and provides runtime services such as PSCI/SMC handling
BL33	Non-secure/normal-world firmware payload	U-Boot in this lab
FIP	Firmware Image Package	Container holding firmware images such as BL2, BL31 and BL33
fiptool	TF-A FIP utility	Creates and inspects FIP files
U-Boot	Bootloader	Runs after TF-A and normally loads the operating system
QEMU virt	Virtual ARM platform	Provides the simulated hardware environment
Trusted Board Boot	TF-A authentication framework	Future stage: cryptographically verifies firmware images
6. Phase 1: Initial TF-A Investigation and Build
Before U-Boot was integrated, TF-A itself was built and inspected. This established that BL1, BL2 and BL31 could be produced and that the host tooling required by TF-A was working.
6.1 Inspect TF-A build targets
make help | head -50
Why: this displayed the TF-A build help and showed the supported QEMU platform and targets such as all, bl1, bl2, bl31, fip, certificates and memmap. It was used to understand what the build system could produce.
6.2 First TF-A build attempt
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=qemu BL33=0
Outcome: the build first stopped because OpenSSL headers were missing. The error was openssl/sha.h not found. This was a host development-package problem, not an ARM64 firmware problem.
sudo apt update
sudo apt install -y libssl-dev
/usr/include/openssl/sha.h
Why: libssl-dev provides the OpenSSL development headers needed by TF-A's cryptographic/build tools. The header path was then checked directly.
6.3 Important correction about BL33=0
The command above also exposed an important build-system detail. BL33 is a path to a BL33 image, not a boolean switch. Using BL33=0 eventually produced the error that 0 did not exist. This was corrected later by supplying the real U-Boot binary.
Makefile:1230: *** 'BL33=0' was specified, but '0' does not exist. Stop.
This failed packaging step did not mean BL1/BL2/BL31 themselves were unusable. Those components were successfully built.
6.4 TF-A artifacts built before U-Boot integration
Artifact	Size recorded	Purpose
build/qemu/release/bl1.bin	22,960 bytes	First boot stage
build/qemu/release/bl2.bin	25,072 bytes	Loads/prepares later firmware
build/qemu/release/bl31.bin	49,255 bytes	EL3 runtime firmware
fiptool	Built successfully	FIP creation/inspection tool
At this point there was no final FIP because no real BL33 payload had yet been supplied.
7. Inspecting BL31 as a Security-Relevant Firmware Component
readelf -h build/qemu/release/bl31/bl31.elf
The ELF header showed ELF64, little-endian, AArch64, executable type, with entry point 0xE090000. This established that BL31 is an ARM64 executable image.
readelf -s build/qemu/release/bl31/bl31.elf | grep -E "bl31|runtime|psci|smc" | head -30
nm build/qemu/release/bl31/bl31.elf | grep -E "bl31|psci|smc" | head -30
Why: symbol inspection connects the binary to its security-relevant responsibilities. The observed symbols included bl31_entrypoint, bl31_main, bl31_warmboot, psci_cpu_on, psci_cpu_suspend, psci_system_suspend and arm_arch_svc_smc_handler. These indicate EL3 initialization and runtime service/PSCI/SMC machinery.
8. TF-A memmap Attempt
make PLAT=qemu memmap
Outcome: this did not fail because of firmware source code. The host build attempted to invoke poetry and reported poetry: No such file or directory. This was recorded as a host tooling issue. It was not necessary to complete the main boot-chain demonstration.
9. Phase 2: Build U-Boot for AArch64
The next goal was to produce the BL33 payload. U-Boot was selected because it is a real bootloader that can execute after TF-A.
9.1 Clone U-Boot
cd ~/qemu/lab3/src
git clone https://source.denx.de/u-boot/u-boot.git
ls
cd u-boot/
git status
git log -1 --oneline
Outcome: the repository cloned successfully. The checkout was on branch main and recorded as b4ac71db13a, tag v2026.10-rc4. The working tree was clean.
9.2 First U-Boot configuration attempt
make qemu_arm64_defconfig
Outcome: the configuration failed because bison was not installed. The Kconfig parser generation required Bison.
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
Outcome: this second command also failed because the previous configuration step had not created .config. This was a consequence of the first failure, not an independent compiler problem.
ls -lh u-boot.bin
Outcome: u-boot.bin did not exist yet.
9.3 Install Bison and Flex
sudo apt update
sudo apt install -y bison flex
bison --version
flex --version
Recorded versions were Bison 3.8.2 and Flex 2.6.4. These are host-side tools used to generate parser/lexer code for U-Boot's configuration system.
9.4 Configure U-Boot successfully
make qemu_arm64_defconfig
ls -lh .config
grep -E 'CONFIG_ARM64|CONFIG_TARGET_QEMU' .config
Outcome: .config was successfully generated. The configuration showed CONFIG_ARM64=y and CONFIG_TARGET_QEMU_ARM_64BIT=y. This confirmed that the target was 64-bit ARM for QEMU.
9.5 U-Boot build and missing GnuTLS header
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
The build progressed through many host tools and then stopped at tools/mkeficapsule.c because gnutls/gnutls.h was missing.
sudo apt update
sudo apt install -y libgnutls28-dev
ls -l /usr/include/gnutls/gnutls.h
pkg-config --modversion gnutls
The GnuTLS header was confirmed to exist. The pkg-config command was also attempted, but pkg-config itself was not installed. That did not prevent continuing because the header was present and the build could be resumed.
A typo was also entered once:
ls -l /usr/include/gnutls/gnutls.hls -l /usr/include/gnutls/gnutls.h
The shell interpreted gnutls.hls as part of a filename. The first intended header check had already succeeded, so the typo was harmless.
9.6 U-Boot successfully built
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
ls -lh u-boot.bin
file u-boot.bin
ls -lh u-boot
Outcome: u-boot.bin was produced at approximately 1.5 MB and the full u-boot ELF was approximately 11 MB.
file u-boot
readelf -h u-boot | grep -E 'Class|Data|Type|Machine|Entry'
./u-boot --version
grep -E 'CONFIG_ARM64=|CONFIG_TARGET_QEMU_ARM_64BIT=' .config
The ELF was identified as an ELF64 AArch64 PIE executable with debug information and not stripped. The raw u-boot.bin was identified only as generic data by the file utility, which is normal for a raw firmware binary.
Running ./u-boot --version on the x86-64 host did not produce a U-Boot version. Instead, the host's transparent AArch64 user-mode emulation attempted to execute it and reported an illegal instruction. This did not invalidate the firmware. The correct plan was to run U-Boot through the AArch64 QEMU system emulator as part of the TF-A boot chain.
10. Integrating U-Boot into TF-A as BL33
cd ~/qemu/lab3/src/trusted-firmware-a
ls -lh ../u-boot/u-boot.bin
ls
make PLAT=qemu clean
Why: the U-Boot raw binary was checked from the TF-A directory, and the previous TF-A build was cleaned because the build inputs were changing. TF-A was then rebuilt with the real BL33 payload.
make CROSS_COMPILE=aarch64-linux-gnu- \
     PLAT=qemu \
     BL33=../u-boot/u-boot.bin \
     all fip
Outcome: BL1, BL2 and BL31 were rebuilt, fiptool was built, and fip.bin was successfully generated. The FIP packaging output explicitly listed BL2, BL31 and BL33.
11. Inspect the FIP
build/qemu/release/tools/fiptool/fiptool info \
    build/qemu/release/fip.bin
The FIP reported three important payloads: Trusted Boot Firmware BL2, EL3 Runtime Firmware BL31, and Non-Trusted Firmware BL33. BL33 was the U-Boot image supplied by the BL33 build option.
find build/qemu/release -maxdepth 2 -type f \
  \( -name "bl1.bin" -o -name "bl2.bin" -o -name "bl31.bin" -o -name "fip.bin" \) -ls
ls -lh \
    build/qemu/release/bl1.bin \
    build/qemu/release/bl2.bin \
    build/qemu/release/bl31.bin \
    build/qemu/release/fip.bin
Recorded sizes: BL1 23 KB, BL2 25 KB, BL31 49 KB and FIP 1.6 MB. The exact FIP size recorded by the file listing was 1,578,735 bytes.
12. Create the QEMU Flash Image
cd ~/qemu/lab3/src/trusted-firmware-a
rm -f flash.bin
dd if=build/qemu/release/bl1.bin \
   of=flash.bin \
   bs=4096 \
   conv=notrunc
dd if=build/qemu/release/fip.bin \
   of=flash.bin \
   bs=4096 \
   seek=64 \
   conv=notrunc
Why: QEMU's flash-based TF-A arrangement uses BL1 at the beginning of the flash image and the FIP at an offset. The seek=64 value means 64 blocks of 4096 bytes, which equals 262,144 bytes or 0x40000.
ls -lh flash.bin
du -h flash.bin
xxd -l 64 flash.bin
xxd -s 0x40000 -l 64 flash.bin
Outcome: flash.bin was approximately 1.8 MB by ls and 1.6 MiB by du. The first xxd showed non-zero ARM64 instructions at offset 0, and the xxd at 0x40000 showed non-zero FIP header/metadata. This provided a simple sanity check that both components were placed in the image.
13. Boot the Complete Chain in QEMU
qemu-system-aarch64 \
    -nographic \
    -machine virt,secure=on \
    -cpu cortex-a57 \
    -bios flash.bin \
    -smp 2 \
    -m 1024
This was the most important runtime command of the lab. It launched the ARM64 QEMU virt machine, enabled the secure world, selected the Cortex-A57 CPU model, used flash.bin as the firmware image, provided two CPUs, and allocated 1 GiB RAM.
14. Observed Boot Output and Interpretation
NOTICE:  Booting Trusted Firmware
NOTICE:  BL1: v2.15.0(release):v2.15.0-655-g0093e24ec
NOTICE:  BL1: Built : 09:28:57, Sep  8 2026
NOTICE:  BL1: Booting BL2
NOTICE:  BL2: v2.15.0(release):v2.15.0-655-g0093e24ec
NOTICE:  BL2: Built : 09:29:03, Sep  8 2026
NOTICE:  BL31: v2.15.0(release):v2.15.0-655-g0093e24ec
NOTICE:  BL31: Built : 09:29:07, Sep  8 2026

U-Boot 2026.10-rc4 (Sep 08 2026 - 09:18:53 +0530)
...
=>
Interpretation: QEMU successfully executed BL1. BL1 transferred control to BL2. BL2 transferred control to BL31. BL31 then successfully transitioned to BL33, which was U-Boot. Reaching the => prompt proves that U-Boot was not only packaged but actually executed.
15. U-Boot Runtime Messages
Message	Meaning	Lab significance
DRAM: 1 GiB	U-Boot sees the emulated RAM	Normal initialization
51 devices, 14 uclasses	U-Boot initialized its device model	U-Boot runtime is functioning
Flash: 32 MiB	Virtual flash device detected	Expected QEMU environment
bad CRC, using default environment	Persistent U-Boot environment was not valid/available	Not a TF-A failure
No USB controllers found	No USB controller is exposed for this configuration	Not required for this lab
eth0: virtio-net#32	Virtual network device exists	Network boot is available
fatal: no kernel available	Automatic bootflow found no kernel	Expected because no OS kernel was supplied
TFTP error: Access violation	TFTP request was rejected/not served	Network boot failed, but firmware boot succeeded
=>	U-Boot command prompt	Final success checkpoint
16. What Was Actually Proven
The lab proved all of the following:
•	The x86-64 host can cross-compile ARM64 firmware.
•	TF-A BL1, BL2 and BL31 can be built for the QEMU platform.
•	BL31 is an AArch64 EL3 runtime image containing PSCI/SMC-related functionality.
•	U-Boot can be configured for the QEMU ARM64 target and built as AArch64 firmware.
•	U-Boot can be supplied to TF-A through the BL33 build option.
•	TF-A can package BL2, BL31 and BL33 into a FIP.
•	BL1 plus the FIP can be placed into a QEMU flash image.
•	QEMU can execute the resulting chain from BL1 through BL2 and BL31 into U-Boot.
•	The final U-Boot prompt proves successful dynamic execution of BL33.
17. What Was NOT Yet Proven
The current lab is a boot-chain demonstration, not yet a cryptographically authenticated secure-boot demonstration.
•	Trusted Board Boot authentication has not yet been enabled.
•	No root-of-trust key hierarchy has yet been generated and analyzed.
•	No deliberate BL33 tampering experiment has yet been performed.
•	No authentication failure has yet been observed.
•	The security properties of the FIP metadata have not yet been experimentally attacked.
•	No OP-TEE/secure-world OS integration has been performed.
•	No systematic SMC/PSCI tracing or EL3 attack-surface analysis has yet been performed.
18. Security Model Emerging from LAB-3
                 Secure / EL3 side
                 -----------------
                       BL31
                  TF-A runtime
                 PSCI / SMC
                       |
                       | controlled transition
                       v
                 Normal world
                 -------------
                       BL33
                     U-Boot
The security boundary is important because BL31 operates at EL3 and can provide services to lower exception levels. U-Boot is the normal-world bootloader payload. The next security phase will ask how firmware authenticity is established before a lower-trust payload such as BL33 is executed.
A key lesson from the lab is: packaging is not the same thing as authentication. A FIP can contain BL33 without the experiment having demonstrated cryptographic proof that BL33 is an authorized image.
19. Complete Command Inventory from This Lab Chat
The following inventory consolidates the shell commands explicitly visible in the conversation and the uploaded terminal transcript. Repeated commands and failed commands are retained where they were actually entered because they are useful for reproducing the lab.
#	Purpose	Command
1	TF-A help	make help | head -50
2	TF-A first build	make CROSS_COMPILE=aarch64-linux-gnu- PLAT=qemu BL33=0
3	Install OpenSSL headers	sudo apt update
4	Install OpenSSL headers	sudo apt install -y libssl-dev
5	Check OpenSSL header	/usr/include/openssl/sha.h
6	Inspect BL31 header	readelf -h build/qemu/release/bl31/bl31.elf
7	Inspect BL31 symbols	readelf -s build/qemu/release/bl31/bl31.elf | grep -E "bl31|runtime|psci|smc" | head -30
8	Inspect BL31 symbols	nm build/qemu/release/bl31/bl31.elf | grep -E "bl31|psci|smc" | head -30
9	TF-A memmap attempt	make PLAT=qemu memmap
10	Clone U-Boot	cd ~/qemu/lab3/src
11	Clone U-Boot	git clone https://source.denx.de/u-boot/u-boot.git
12	List source dirs	ls
13	Enter U-Boot	cd u-boot/
14	Git status	git status
15	Git version record	git log -1 --oneline
16	U-Boot config attempt	make qemu_arm64_defconfig
17	U-Boot build attempt	make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
18	Check missing binary	ls -lh u-boot.bin
19	Check Bison	bison --version
20	Check Flex	flex --version
21	Install Bison/Flex	sudo apt update
22	Install Bison/Flex	sudo apt install -y bison flex
23	Configure U-Boot	make qemu_arm64_defconfig
24	Check .config	ls -lh .config
25	Check ARM64 config	grep -E 'CONFIG_ARM64|CONFIG_TARGET_QEMU' .config
26	Build U-Boot	make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
27	Check GnuTLS header	ls -l /usr/include/gnutls/gnutls.h
28	Typoed header command	ls -l /usr/include/gnutls/gnutls.hls -l /usr/include/gnutls/gnutls.h
29	Check pkg-config	pkg-config --modversion gnutls
30	Check U-Boot raw binary	ls -lh u-boot.bin
31	Identify U-Boot raw binary	file u-boot.bin
32	Check U-Boot ELF	ls -lh u-boot
33	List U-Boot tree	ls
34	Identify U-Boot ELF	file u-boot
35	Inspect U-Boot ELF header	readelf -h u-boot | grep -E 'Class|Data|Type|Machine|Entry'
36	Attempt host execution	./u-boot --version
37	Check both U-Boot outputs	ls -lh u-boot u-boot.bin
38	Check U-Boot config	grep -E 'CONFIG_ARM64=|CONFIG_TARGET_QEMU_ARM_64BIT=' .config
39	Repeated config check	grep -E 'CONFIG_ARM64=|CONFIG_TARGET_QEMU_ARM_64BIT=' .config
40	Enter TF-A	cd ~/qemu/lab3/src/trusted-firmware-a
41	Check BL33 input	ls -lh ../u-boot/u-boot.bin
42	List TF-A tree	ls
43	Clean TF-A	make PLAT=qemu clean
44	Build TF-A + FIP	make CROSS_COMPILE=aarch64-linux-gnu- \
     PLAT=qemu \
     BL33=../u-boot/u-boot.bin \
     all fip
45	FIP inspection	build/qemu/release/tools/fiptool/fiptool info \
    build/qemu/release/fip.bin
46	Find TF-A artifacts	find build/qemu/release -maxdepth 2 -type f \
  \( -name "bl1.bin" -o -name "bl2.bin" -o -name "bl31.bin" -o -name "fip.bin" \) -ls
47	List TF-A artifact sizes	ls -lh \
    build/qemu/release/bl1.bin \
    build/qemu/release/bl2.bin \
    build/qemu/release/bl31.bin \
    build/qemu/release/fip.bin
48	Enter TF-A again	cd ~/qemu/lab3/src/trusted-firmware-a
49	Remove old flash image	rm -f flash.bin
50	Place BL1 in flash	dd if=build/qemu/release/bl1.bin \
   of=flash.bin \
   bs=4096 \
   conv=notrunc
51	Place FIP at 0x40000	dd if=build/qemu/release/fip.bin \
   of=flash.bin \
   bs=4096 \
   seek=64 \
   conv=notrunc
52	Check flash size	ls -lh flash.bin
53	Check flash disk usage	du -h flash.bin
54	Inspect BL1 area	xxd -l 64 flash.bin
55	Inspect FIP area	xxd -s 0x40000 -l 64 flash.bin
56	Boot QEMU	qemu-system-aarch64 \
    -nographic \
    -machine virt,secure=on \
    -cpu cortex-a57 \
    -bios flash.bin \
    -smp 2 \
    -m 1024
20. Command Count
Counting the explicit shell command entries preserved in the conversation/transcript, including failed attempts, repeated commands, and the one typoed command, the inventory above contains 56 command entries. This is a transcript-based count, not a count of every internal shell operation performed by make, because make itself executes many subcommands internally. If those compiler/linker subcommands were counted, the number would be hundreds or thousands rather than a useful lab-command count.
21. Final Artifact Checklist
Artifact	Expected location	Status
TF-A BL1	~/qemu/lab3/src/trusted-firmware-a/build/qemu/release/bl1.bin	Built
TF-A BL2	~/qemu/lab3/src/trusted-firmware-a/build/qemu/release/bl2.bin	Built
TF-A BL31	~/qemu/lab3/src/trusted-firmware-a/build/qemu/release/bl31.bin	Built
TF-A fiptool	~/qemu/lab3/src/trusted-firmware-a/build/qemu/release/tools/fiptool/fiptool	Built
FIP	~/qemu/lab3/src/trusted-firmware-a/build/qemu/release/fip.bin	Built and inspected
U-Boot ELF	~/qemu/lab3/src/u-boot/u-boot	Built
U-Boot raw image	~/qemu/lab3/src/u-boot/u-boot.bin	Built
QEMU flash image	~/qemu/lab3/src/trusted-firmware-a/flash.bin	Created and booted
22. Final LAB-3 Conclusion
LAB-3 successfully established a complete ARM64 firmware execution chain on QEMU. The work started with the host build environment, resolved missing build dependencies, built TF-A, examined BL31 at the ELF/symbol level, built U-Boot as an AArch64 target, packaged U-Boot into TF-A's FIP as BL33, constructed a flash image, and finally booted the complete chain.
The strongest experimental result is the runtime evidence: QEMU printed the TF-A BL1, BL2 and BL31 stages and then displayed U-Boot 2026.10-rc4 with a working command prompt. This proves that the separate build artifacts were correctly integrated and executed.
The next research stage is Trusted Board Boot and firmware authentication. That stage should build on the working chain rather than changing several variables at once. Once authentication is enabled, a controlled modification of BL33 can be used to demonstrate the difference between an executable firmware package and an authenticated trusted boot chain.
Appendix A. Useful Reproduction Sequence
For a clean reproduction of the successful path, the essential sequence is:
# 1. Build U-Boot
cd ~/qemu/lab3/src/u-boot
make qemu_arm64_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

# 2. Build TF-A and package U-Boot as BL33
cd ~/qemu/lab3/src/trusted-firmware-a
make PLAT=qemu clean
make CROSS_COMPILE=aarch64-linux-gnu- \
     PLAT=qemu \
     BL33=../u-boot/u-boot.bin \
     all fip

# 3. Inspect FIP
build/qemu/release/tools/fiptool/fiptool info \
    build/qemu/release/fip.bin

# 4. Build flash image
rm -f flash.bin
dd if=build/qemu/release/bl1.bin of=flash.bin bs=4096 conv=notrunc
dd if=build/qemu/release/fip.bin of=flash.bin bs=4096 seek=64 conv=notrunc

# 5. Boot
qemu-system-aarch64 \
    -nographic \
    -machine virt,secure=on \
    -cpu cortex-a57 \
    -bios flash.bin \
    -smp 2 \
    -m 1024
Appendix B. Key Lessons to Remember
•	BL1, BL2 and BL31 are TF-A stages; BL33 is the normal-world payload in this lab.
•	BL31 is the EL3 runtime firmware and is therefore a critical security boundary.
•	U-Boot's u-boot ELF is useful for analysis; u-boot.bin is the raw payload used for boot packaging.
•	A raw .bin file may be reported simply as 'data' by file because it lacks ELF metadata.
•	Host tools such as Bison, Flex and GnuTLS headers are needed to build firmware even though the final firmware target is AArch64.
•	A successful FIP build proves packaging, not cryptographic authenticity.
•	The U-Boot TFTP/kernel warnings occurred after the trusted firmware chain had already succeeded.
•	The => prompt is the final runtime checkpoint of this completed stage.
