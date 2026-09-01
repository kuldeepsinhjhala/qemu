# Lab 1 Detailed Write-up: AArch64 Cross-Compilation, ELF Analysis, and QEMU Execution

This is the complete record of **QEMU Lab 1A**. It covers what we built, every important command, your actual addresses/output, the difference between ELF sections and program segments, how Linux automatically invoked QEMU, and the complete execution path.

---

# QEMU Lab 1A

## AArch64 Cross-Compilation → ELF → Disassembly → QEMU User-Mode Execution

---

# 1. Lab Objective

The objective of this lab was to establish the basic relationship between:

```text
C source code
      ↓
AArch64 cross-compiler
      ↓
ARM64 ELF executable
      ↓
ELF inspection
      ↓
AArch64 machine instructions
      ↓
QEMU AArch64 emulation
      ↓
Program execution
```

The lab was intentionally performed before working with TF-A.

The purpose was to understand the low-level building blocks that we will later use when analyzing:

```text
TF-A
BL1
BL2
BL31
FIP
U-Boot
```

The key lesson is:

> A program's source code, ELF representation, machine instructions, memory layout, entry point, and execution environment are different layers of the same software.

---

# 2. Host Environment

The physical development machine is:

```text
Architecture: x86-64
CPU: Intel Core i3-6006U
OS: Ubuntu
```

The important architectural relationship is:

```text
Physical machine
       │
       │ x86-64
       ▼
Ubuntu
       │
       │ AArch64 cross compilation
       ▼
ARM64 program
       │
       │ QEMU
       ▼
ARM64 execution
```

The physical CPU is x86-64, while the program we created targets AArch64.

---

# 3. Lab Directory

The lab was created inside the QEMU working directory:

```text
~/qemu/lab1
```

The main files are:

```text
~/qemu/lab1/
├── hello.c
├── hello
└── hello_analysis.txt
```

---

# 4. Program Source Code

The source file was:

```text
hello.c
```

Code:

```c
int main(void)
{
    return 42;
}
```

The program does not print anything.

Its only operation is:

```text
main()
   ↓
return 42
```

The value `42` becomes the program's exit status.

---

# 5. AArch64 Cross Compiler

The compiler used was:

```text
aarch64-linux-gnu-gcc
```

Verification:

```bash
aarch64-linux-gnu-gcc --version
```

Actual result:

```text
aarch64-linux-gnu-gcc (Ubuntu 15.2.0-16ubuntu1) 15.2.0
```

Target architecture:

```bash
aarch64-linux-gnu-gcc -dumpmachine
```

Result:

```text
aarch64-linux-gnu
```

Location:

```bash
which aarch64-linux-gnu-gcc
```

Result:

```text
/usr/bin/aarch64-linux-gnu-gcc
```

## What this compiler does

The physical machine is:

```text
x86-64
```

but the compiler generates:

```text
AArch64
```

Therefore:

```text
x86-64 host
      │
      │ aarch64-linux-gnu-gcc
      ▼
AArch64 executable
```

This is called **cross-compilation**.

---

# 6. Compile the Program

Command:

```bash
aarch64-linux-gnu-gcc -static -o hello hello.c
```

Breakdown:

```text
aarch64-linux-gnu-gcc
    → AArch64 cross compiler

-static
    → statically link libraries

-o hello
    → create output file named hello

hello.c
    → input source file
```

Result:

```text
hello.c
   ↓
AArch64 GCC
   ↓
hello
```

The generated executable was approximately:

```text
689 KB
```

Verified using:

```bash
ls -lh hello
```

---

# 7. Why the Binary Is Large

The source code is tiny:

```c
int main(void)
{
    return 42;
}
```

Yet the executable is approximately:

```text
689 KB
```

The reason is:

```bash
-static
```

The executable contains statically linked runtime/library code.

Therefore the binary contains much more than our two-line function.

This is why `objdump -d hello` produced a very large amount of assembly.

---

# 8. Identify the Binary

Command:

```bash
file hello
```

Actual result:

```text
hello: ELF 64-bit LSB executable, ARM aarch64,
version 1 (GNU/Linux), statically linked,
for GNU/Linux 3.7.0, not stripped
```

## What this tells us

### ELF

The file uses the:

```text
Executable and Linkable Format
```

### 64-bit

It is an ELF64 executable.

### ARM aarch64

The executable targets ARM64.

### LSB

The binary uses little-endian byte ordering.

### Statically linked

Runtime/library code is included in the executable.

### Not stripped

Symbol information such as `main` remains available.

---

# 9. ELF Header

Command:

```bash
readelf -h hello
```

Important output:

```text
Class:              ELF64
Data:               2's complement, little endian
OS/ABI:              UNIX - GNU
Type:               EXEC (Executable file)
Machine:            AArch64
Version:            0x1
Entry point address: 0x4005c0
```

## Important values

```text
ELF class:
ELF64

Architecture:
AArch64

Entry point:
0x4005c0
```

---

# 10. What Is the Entry Point?

The ELF entry point was:

```text
0x4005c0
```

This means:

> The initial execution address specified by the executable is `0x4005c0`.

However, this is **not ****`main()`**.

Our `main()` address is:

```text
0x400740
```

Therefore:

```text
Program starts
      ↓
0x4005c0
      ↓
startup/runtime code
      ↓
main()
      ↓
0x400740
```

This is an extremely important concept.

For a normal Linux program:

```text
ELF entry point
      ↓
C runtime startup
      ↓
main()
```

For firmware, we will later encounter a more direct firmware-specific entry path.

---

# 11. Inspect ELF Sections

Command:

```bash
readelf -S hello
```

This displays the ELF **section table**.

Your executable contained 25 sections.

Important sections included:

```text
.init
.plt
.text
.fini
.rodata
.eh_frame
.tdata
.tbss
.init_array
.fini_array
.data.rel.ro
.got
.got.plt
.data
.bss
.symtab
.strtab
```

---

# 12. What Is an ELF Section?

A section is a logical organization of the executable.

Think:

```text
ELF
│
├── .text
├── .rodata
├── .data
├── .bss
├── symbol information
└── other metadata
```

Different sections have different purposes.

---

# 13. Important Sections

## `.text`

Your output:

```text
[ 5] .text
Address: 0000000000400300
Offset:  00000300
Size:    000000000005abd8
Flags:   AX
```

`.text` contains executable machine code.

The flags:

```text
A
X
```

mean:

```text
A = Allocated
X = Executable
```

Therefore:

```text
.text
   ↓
executable code
```

Our `main()` is inside `.text`.

---

## `.rodata`

Contains read-only data.

Conceptually:

```text
.rodata
   ↓
read-only constants/data
```

---

## `.data`

Contains initialized writable data.

```text
.data
   ↓
initialized writable variables
```

---

## `.bss`

Contains uninitialized/zero-initialized data.

Important property:

```text
.bss
```

usually does not need to store all the zero bytes in the executable file.

The loader creates the required memory.

---

## `.symtab`

Contains symbols.

Your output showed:

```text
.symtab
```

This allows tools such as:

```bash
nm
```

to identify symbols such as:

```text
main
```

---

# 14. Find `main`

Command:

```bash
aarch64-linux-gnu-nm hello | grep ' main$'
```

Actual result:

```text
0000000000400740 T main
```

Therefore:

```text
main = 0x400740
```

The `T` indicates that `main` is located in the executable code/text area.

---

# 15. Disassemble Only `main`

Command:

```bash
aarch64-linux-gnu-objdump -d --disassemble=main hello
```

Actual result:

```text
0000000000400740 <main>:
  400740:       52800540        mov     w0, #0x2a
  400744:       d65f03c0        ret
```

This is one of the most important results of the lab.

Our C code:

```c
return 42;
```

became:

```text
mov w0, #0x2a
ret
```

And:

```text
0x2a = 42 decimal
```

Therefore:

```text
main()
   ↓
W0 = 42
   ↓
return
```

---

# 16. Why `W0`?

AArch64 has 64-bit registers:

```text
X0
```

and their lower 32-bit views:

```text
W0
```

Because C `int` is 32-bit, the compiler uses:

```text
W0
```

for the return value.

Conceptually:

```text
X0
┌────────────────────────────────────────┐
│             64-bit register            │
└────────────────────────────────────────┘
└────────────── W0 ──────────────┘
                32 bits
```

The instruction:

```text
mov w0, #0x2a
```

places `42` into `W0`.

---

# 17. The `ret` Instruction

The second instruction:

```text
d65f03c0    ret
```

means:

```text
return from function
```

Therefore the entire `main()` is effectively:

```text
main
 │
 ├── W0 = 42
 │
 └── return
```

---

# 18. Full `objdump` vs Targeted `objdump`

Originally:

```bash
aarch64-linux-gnu-objdump -d hello
```

was used.

This disassembled all executable code.

Because the executable is statically linked, the output was huge.

For focused analysis:

```bash
aarch64-linux-gnu-objdump -d --disassemble=main hello
```

is much more useful.

General rule:

```text
objdump -d
    → inspect lots/all executable code

objdump -d --disassemble=function
    → inspect one function
```

---

# 19. Program Headers / Segments

Next command:

```bash
readelf -l hello
```

This displays **program headers**.

The output showed:

```text
There are 7 program headers
```

Most importantly, there were two `LOAD` segments.

---

# 20. Section vs Segment

This distinction is critical.

## Sections

Use:

```bash
readelf -S hello
```

Sections describe the logical organization of the ELF.

Think:

```text
Sections
   ↓
How the executable is organized
```

## Segments

Use:

```bash
readelf -l hello
```

Segments describe how parts of the executable are loaded into memory.

Think:

```text
Segments
   ↓
How the executable is loaded into memory
```

Therefore:

```text
ELF
│
├── Sections
│     └── logical organization
│
└── Segments
      └── memory/loading organization
```

---

# 21. First LOAD Segment

Your output:

```text
LOAD
VirtAddr 0x0000000000400000
PhysAddr 0x0000000000400000
FileSiz  0x0000000000082928
MemSiz   0x0000000000082928
Flags    R E
Align    0x10000
```

Important values:

```text
Virtual address:
0x400000

Physical address:
0x400000

File size:
0x82928

Memory size:
0x82928

Permissions:
R E
```

`R E` means:

```text
R = Read
E = Execute
```

This is the executable part of the program.

---

# 22. What Does This LOAD Segment Contain?

Your section-to-segment mapping showed:

```text
LOAD
├── .note.gnu.build-id
├── .rela.plt
├── .init
├── .plt
├── .text
├── .fini
├── .rodata
├── .eh_frame
├── .gcc_except_table
└── .note.ABI-tag
```

So:

```text
LOAD #1
│
├── executable code
│     └── .text
│
└── read-only information
      └── .rodata
```

Our `main()`:

```text
0x400740
```

is inside this executable memory region.

---

# 23. Second LOAD Segment

Your output:

```text
LOAD
VirtAddr 0x000000000049c498
PhysAddr 0x000000000049c498
FileSiz  0x542c
MemSiz   0xa910
Flags    RW
Align    0x10000
```

Important values:

```text
Virtual address:
0x49c498

Physical address:
0x49c498

File size:
0x542c

Memory size:
0xa910

Permissions:
RW
```

`RW` means:

```text
R = Read
W = Write
```

This is primarily the writable-data region.

---

# 24. What Does the Second LOAD Segment Contain?

Your mapping showed:

```text
LOAD
├── .tdata
├── .init_array
├── .fini_array
├── .data.rel.ro
├── .got
├── .got.plt
├── .data
└── .bss
```

Therefore:

```text
LOAD #2
│
├── writable data
├── global data
├── .data
└── .bss
```

---

# 25. Why Is File Size Different From Memory Size?

For the second segment:

```text
FileSiz = 0x542c
MemSiz  = 0xa910
```

The memory size is larger.

One reason is `.bss`.

For example:

```c
int counter;
```

requires memory, but it does not need thousands of zero bytes stored inside the executable file.

Therefore:

```text
FileSiz
    ↓
Data physically present in the file

MemSiz
    ↓
Memory required when running
```

This distinction becomes important when studying firmware memory initialization.

---

# 26. Important Addresses From This Lab

| Item                         |    Address |
| ---------------------------- | ---------: |
| First LOAD virtual address   | `0x400000` |
| First LOAD physical address  | `0x400000` |
| `.text` address              | `0x400300` |
| ELF entry point              | `0x4005c0` |
| `main()`                     | `0x400740` |
| Second LOAD virtual address  | `0x49c498` |
| Second LOAD physical address | `0x49c498` |

The key relationship is:

```text
0x400000
   │
   ├── .text starts at 0x400300
   │
   ├── entry point at 0x4005c0
   │
   └── main at 0x400740
```

---

# 27. Important Observation: Entry Point ≠ `main`

Our actual binary proves:

```text
Entry point = 0x4005c0

main = 0x400740
```

Therefore:

```text
0x4005c0
    ↓
startup/runtime code
    ↓
main()
    ↓
0x400740
```

This is a very important concept to carry into TF-A.

When we inspect TF-A later, we will ask:

```text
Where does BL1 begin?

Where does BL2 begin?

Where does BL31 begin?
```

We will not automatically assume that the first interesting C function is the actual CPU entry point.

---

# 28. QEMU User-Mode Emulator

We installed:

```bash
sudo apt install qemu-user
```

This installed:

```text
qemu-user
qemu-user-binfmt
```

Verification:

```bash
qemu-aarch64 --version
```

Result:

```text
qemu-aarch64 version 10.2.1
```

Location:

```bash
which qemu-aarch64
```

Result:

```text
/usr/bin/qemu-aarch64
```

---

# 29. What Is `qemu-aarch64`?

It is QEMU's **AArch64 user-mode emulator**.

Its purpose is to run an ARM64 Linux userspace program.

Conceptually:

```text
AArch64 Linux application
        ↓
qemu-aarch64
        ↓
ARM64 instruction emulation
```

This is different from:

```text
qemu-system-aarch64
```

which emulates a complete ARM64 machine.

---

# 30. Explicit QEMU Execution

Command:

```bash
qemu-aarch64 ./hello
```

The program produced no terminal output.

That is correct.

Why?

Because the program only does:

```c
return 42;
```

It doesn't contain `printf()`.

To inspect the exit status:

```bash
echo $?
```

Result:

```text
42
```

Therefore:

```text
hello
 ↓
main()
 ↓
W0 = 42
 ↓
return
 ↓
exit status = 42
```

---

# 31. Unexpected Observation: `./hello` Also Worked

We then executed:

```bash
./hello
```

and:

```bash
echo $?
```

Result:

```text
42
```

This initially appears strange because we did not explicitly invoke:

```bash
qemu-aarch64
```

The reason is:

```text
qemu-user-binfmt
```

---

# 32. What Is `binfmt_misc`?

Linux provides a mechanism called:

```text
binfmt_misc
```

It allows the kernel to recognize executable formats/architectures and delegate them to an appropriate interpreter.

Installing:

```text
qemu-user-binfmt
```

registers QEMU's user-mode emulators with Linux.

Conceptually:

```text
./hello
   ↓
Linux kernel
   ↓
Inspect ELF
   ↓
Machine = AArch64
   ↓
Host = x86-64
   ↓
Check binfmt_misc
   ↓
AArch64 handler registered
   ↓
qemu-aarch64
   ↓
ARM64 execution
```

So when we type:

```bash
./hello
```

QEMU is still involved.

We simply didn't invoke it manually.

---

# 33. Explicit vs Automatic Execution

## Explicit

```bash
qemu-aarch64 ./hello
```

Flow:

```text
Shell
 ↓
qemu-aarch64
 ↓
hello
```

## Automatic

```bash
./hello
```

Flow:

```text
Shell
 ↓
Linux kernel
 ↓
binfmt_misc
 ↓
qemu-aarch64
 ↓
hello
```

Both ultimately result in ARM64 emulation.

---

# 34. Complete Lab Execution Flow

The complete system can now be represented as:

```text
                    x86-64 Ubuntu Host
                           │
                           │
                    hello.c source
                           │
                           ▼
              aarch64-linux-gnu-gcc
                           │
                           │ Cross compilation
                           ▼
                     hello ELF
                           │
             ┌─────────────┼──────────────┐
             │             │              │
             ▼             ▼              ▼
          file          readelf        objdump
             │             │              │
             │             │              │
             │        ELF structure    ARM64
             │        entry point      instructions
             │        sections
             │        segments
             │
             └─────────────┬──────────────┘
                           │
                           ▼
                    AArch64 executable
                           │
                           ▼
                     qemu-aarch64
                           │
                           ▼
                    ARM64 emulation
                           │
                           ▼
                         main()
                           │
                           ▼
                      W0 = 42
                           │
                           ▼
                         ret
                           │
                           ▼
                     exit status 42
```

---

# 35. Commands Used in the Lab

## Environment

```bash
uname -m
lscpu
```

## Compiler

```bash
aarch64-linux-gnu-gcc --version
aarch64-linux-gnu-gcc -dumpmachine
which aarch64-linux-gnu-gcc
```

## Compile

```bash
aarch64-linux-gnu-gcc -static -o hello hello.c
```

## Binary identification

```bash
file hello
```

## ELF header

```bash
readelf -h hello
```

## ELF sections

```bash
readelf -S hello
```

## ELF program headers / segments

```bash
readelf -l hello
```

## Disassembly

```bash
aarch64-linux-gnu-objdump -d hello
```

Focused disassembly:

```bash
aarch64-linux-gnu-objdump -d --disassemble=main hello
```

## Symbols

```bash
aarch64-linux-gnu-nm hello | grep ' main$'
```

## QEMU

```bash
qemu-aarch64 --version
which qemu-aarch64
```

## Execute explicitly

```bash
qemu-aarch64 ./hello
echo $?
```

## Execute automatically through binfmt

```bash
./hello
echo $?
```

---

# 36. Command Tree

The current lab can be reproduced using this command structure:

```text
~/qemu/
│
└── lab1/
    │
    ├── hello.c
    │     └── [nano hello.c]
    │
    ├── hello
    │     └── [aarch64-linux-gnu-gcc -static -o hello hello.c]
    │
    ├── Binary information
    │     ├── [file hello]
    │     └── [ls -lh hello]
    │
    ├── ELF information
    │     ├── [readelf -h hello]
    │     │     ├── Machine → AArch64
    │     │     └── Entry → 0x4005c0
    │     │
    │     ├── [readelf -S hello]
    │     │     ├── .text → 0x400300
    │     │     ├── .data
    │     │     ├── .bss
    │     │     └── .symtab
    │     │
    │     └── [readelf -l hello]
    │           ├── LOAD 1 → 0x400000 → R E
    │           └── LOAD 2 → 0x49c498 → R W
    │
    ├── Symbols
    │     └── [aarch64-linux-gnu-nm hello | grep ' main$']
    │             └── main → 0x400740
    │
    ├── Machine code
    │     ├── [aarch64-linux-gnu-objdump -d hello]
    │     └── [aarch64-linux-gnu-objdump -d --disassemble=main hello]
    │             ├── mov w0, #0x2a
    │             └── ret
    │
    └── QEMU execution
          ├── [qemu-aarch64 --version]
          ├── [which qemu-aarch64]
          ├── [qemu-aarch64 ./hello]
          │      └── [echo $?] → 42
          │
          └── [./hello]
                 └── binfmt_misc → qemu-aarch64
                        └── [echo $?] → 42
```

---

# 37. How to Generate the Analysis File Again

The complete analysis was saved using:

```bash
{
    echo "========== file hello =========="
    file hello
    echo

    echo "========== readelf -h hello =========="
    readelf -h hello
    echo

    echo "========== readelf -S hello =========="
    readelf -S hello
    echo

    echo "========== objdump -d hello =========="
    aarch64-linux-gnu-objdump -d hello
    echo

    echo "========== nm: main =========="
    aarch64-linux-gnu-nm hello | grep ' main$'
} > hello_analysis.txt 2>&1
```

Read it with:

```bash
less hello_analysis.txt
```

`less` is preferable to `cat` for large output because it allows scrolling and searching.

---

# 38. Key Concepts Learned

## Cross compilation

```text
x86-64 machine
      ↓
AArch64 GCC
      ↓
ARM64 binary
```

## ELF

```text
hello
 ↓
ELF64
 ↓
AArch64 executable
```

## Entry point

```text
Entry = 0x4005c0
```

This is where the executable's initial execution begins.

## `main`

```text
main = 0x400740
```

`main` is reached later through the program's startup/runtime path.

## Sections

```text
readelf -S
```

shows logical executable organization.

Important:

```text
.text → executable code
.data → initialized writable data
.bss  → zero/uninitialized data
```

## Segments

```text
readelf -l
```

shows loadable memory regions.

Important:

```text
LOAD @ 0x400000 → R E
LOAD @ 0x49c498 → R W
```

## Assembly

```text
return 42
```

became:

```text
mov w0, #0x2a
ret
```

## QEMU

```text
qemu-aarch64
```

allows the x86-64 machine to execute the AArch64 program through emulation.

## binfmt_misc

Allows Linux to automatically invoke QEMU when executing a foreign-architecture binary.

---

# 39. Most Important Mental Model

The most important result of Lab 1 is this:

```text
                    SOURCE LEVEL
                         │
                         │ C
                         ▼
                  int main() {

                    return 42;
                  }
                         │
                         │ Compiler
                         ▼
                  MACHINE LEVEL
                         │
                         │ AArch64
                         ▼
                 mov w0, #0x2a
                 ret
                         │
                         │ stored in
                         ▼
                    ELF BINARY
                         │
              ┌──────────┴──────────┐
              │                     │
          Sections              Segments
              │                     │
       .text, .data,          LOAD R E
       .bss, etc.             LOAD R W
              │                     │
              └──────────┬──────────┘
                         │
                         ▼
                  EXECUTION LEVEL
                         │
                         ▼
                    QEMU ARM64
                         │
                         ▼
                  ARM64 CPU model
                         │
                         ▼
                     main()
                         │
                         ▼
                      W0 = 42
                         │
                         ▼
                       ret
                         │
                         ▼
                    exit status 42
```

---

# 40. Connection to the Future TF-A Labs

Everything we learned here will be reused.

Instead of:

```text
hello
```

we will eventually inspect:

```text
BL1
BL2
BL31
BL33
FIP
```

Instead of asking:

```text
Where is main?
```

we'll ask:

```text
Where does BL1 start?
Where does BL2 start?
Where does BL31 start?
```

Instead of simply looking at:

```text
.text
```

we'll investigate TF-A's memory layout.

Instead of:

```text
return 42
```

we'll inspect actual firmware operations such as:

```text
CPU initialization
memory initialization
UART initialization
image loading
authentication
EL3 setup
SMC handling
handoff
```

And instead of only:

```text
qemu-aarch64
```

we will use:

```text
qemu-system-aarch64
```

to emulate an entire ARM64 machine:

```text
QEMU
│
├── ARM CPU
├── RAM
├── UART
├── GIC
├── Timer
├── Device Tree
└── other virtual hardware
       │
       ▼
      TF-A
       │
       ├── BL1
       ├── BL2
       └── BL31
```

## Lab 1A Conclusion

The lab successfully demonstrated:

```text
✓ AArch64 cross compilation
✓ ELF identification
✓ ELF header analysis
✓ Entry point identification
✓ Section analysis
✓ Segment analysis
✓ Memory addresses
✓ Symbol identification
✓ AArch64 disassembly
✓ ARM64 register usage
✓ QEMU user-mode installation
✓ Explicit QEMU execution
✓ Automatic QEMU execution through binfmt_misc
✓ Exit-status verification
```

The most important distinction to retain before moving forward is:

```text
SECTION ≠ SEGMENT ≠ ENTRY POINT ≠ FUNCTION
```

They describe different things:

```text
Section
  → logical ELF organization

Segment
  → memory/loading organization

Entry point
  → initial execution address

Function
  → a callable piece of code
```

This distinction will become much more important when we start analyzing TF-A.

# What is ELF?

**ELF** stands for **Executable and Linkable Format**.

It is a standard format used by Linux and many Unix-like systems to represent things such as:

- Executable programs
    
- Object files
    
- Shared libraries
    
- Some firmware/toolchain artifacts
    

In our Lab 1, the file:

```text
hello
```

is an **ELF executable**.

---

## 1. Why do we need ELF?

Suppose we have:

```c
int main(void)
{
    return 42;
}
```

The compiler turns this into machine code:

```text
AArch64 machine instructions
```

But the CPU cannot just look at a random pile of machine-code bytes and know:

- Where does the program start?
    
- Which architecture is this for?
    
- Which parts are executable?
    
- Where should data be placed?
    
- What memory regions need to be loaded?
    
- What symbols/functions exist?
    

ELF provides this structure.

Think of ELF as a **container with a map** around the machine code.

```text
              ELF executable
        ┌────────────────────────┐
        │ ELF Header             │
        │                        │
        │ "I am AArch64"         │
        │ "I am 64-bit"          │
        │ "Start at 0x4005c0"    │
        │                        │
        ├────────────────────────┤
        │ Program Headers        │
        │                        │
        │ "Load this into memory"│
        │                        │
        ├────────────────────────┤
        │ Sections               │
        │                        │
        │ .text                  │
        │ .rodata                │
        │ .data                  │
        │ .bss                   │
        │ etc.                   │
        │                        │
        ├────────────────────────┤
        │ Symbol Table           │
        │                        │
        │ main → 0x400740        │
        │                        │
        └────────────────────────┘
```

---

# 2. Your `hello` is an ELF

You proved this with:

```bash
file hello
```

Your output started with:

```text
hello: ELF 64-bit LSB executable, ARM aarch64
```

So we know:

```text
ELF
 ↓
64-bit
 ↓
AArch64
 ↓
Executable
```

---

# 3. The ELF Header

We inspected it with:

```bash
readelf -h hello
```

You got:

```text
Class:              ELF64
Machine:            AArch64
Entry point address: 0x4005c0
```

The **ELF header** is essentially the first piece of information describing the file.

It tells tools/loaders things such as:

```text
What format?
      ↓
ELF

32-bit or 64-bit?
      ↓
ELF64

Which architecture?
      ↓
AArch64

Where should initial execution begin?
      ↓
0x4005c0
```

---

# 4. ELF Sections

We used:

```bash
readelf -S hello
```

This showed sections such as:

```text
.text
.rodata
.data
.bss
.symtab
.strtab
```

Think of sections as **logical compartments**.

### `.text`

Contains executable instructions.

Your `.text` starts at:

```text
0x400300
```

Our `main()` is inside it:

```text
main = 0x400740
```

### `.rodata`

Read-only data.

### `.data`

Initialized writable data.

### `.bss`

Uninitialized/zero-initialized data.

### `.symtab`

Symbol information, such as:

```text
main → 0x400740
```

---

# 5. ELF Program Segments

We used:

```bash
readelf -l hello
```

This is different from `readelf -S`.

You found two important `LOAD` segments.

### First

```text
LOAD
VirtAddr: 0x400000
Flags:    R E
```

Meaning roughly:

```text
0x400000
   ↓
readable + executable memory
   ↓
.text and other read/execute content
```

### Second

```text
LOAD
VirtAddr: 0x49c498
Flags:    R W
```

Meaning:

```text
0x49c498
   ↓
readable + writable memory
   ↓
.data / .bss and related data
```

So:

```text
ELF
│
├── Sections
│     ├── .text
│     ├── .rodata
│     ├── .data
│     └── .bss
│
└── Segments
      ├── LOAD R E
      └── LOAD R W
```

### Remember this distinction

**Sections** are primarily about how the binary is logically organized.

**Segments** are primarily about what gets loaded into memory and with what properties.

---

# 6. ELF also knows about symbols

We ran:

```bash
aarch64-linux-gnu-nm hello | grep ' main$'
```

and got:

```text
0000000000400740 T main
```

So ELF's symbol information lets tools associate:

```text
main
   ↓
0x400740
```

Then `objdump` lets us inspect what's actually at that address:

```bash
aarch64-linux-gnu-objdump -d --disassemble=main hello
```

Result:

```text
0000000000400740 <main>:
  400740:  52800540  mov w0, #0x2a
  400744:  d65f03c0  ret
```

Now we have:

```text
C source
   │
   │ return 42
   ▼
main()
   │
   │ symbol
   ▼
0x400740
   │
   │ disassembly
   ▼
mov w0, #0x2a
ret
```

That's the real value of understanding ELF.

---

# 7. ELF vs the actual machine code

This distinction is important.

**ELF is not the machine code itself.**

Rather:

```text
ELF
│
├── machine code
├── information about that code
├── loading information
├── memory organization
├── symbols
└── other metadata
```

The actual AArch64 instructions are primarily inside `.text`.

For your `main()`:

```text
.text
   │
   └── 0x400740
          │
          ├── mov w0, #42
          └── ret
```

---

# 8. Why ELF matters for your TF-A work

This is where Lab 1 connects directly to your research.

When we eventually build TF-A, we won't just say:

> "Here is a binary. Run it."

We'll need to understand things like:

```text
What architecture is this?
        ↓
AArch64

Where is the code?
        ↓
.text / loadable regions

Where does execution begin?
        ↓
entry point / firmware entry

Where is a particular function?
        ↓
symbol → address

What gets loaded into memory?
        ↓
program segments

What addresses does the firmware expect?
        ↓
linker/load configuration
```

You'll use the same tools:

```bash
file
readelf
nm
objdump
```

to investigate TF-A.

---

# 9. The simplest mental model

Remember ELF as:

> **A structured package containing executable code plus the information needed to understand and load that code.**

For our `hello`:

```text
hello
 │
 └── ELF
      │
      ├── "I'm AArch64"
      │
      ├── "I'm 64-bit"
      │
      ├── "Start execution at 0x4005c0"
      │
      ├── ".text is executable code"
      │
      ├── ".data/.bss contain data"
      │
      ├── "main is at 0x400740"
      │
      └── "Here are the actual AArch64 instructions"
```

And that is why **ELF is one of the first things you need to understand before seriously analyzing TF-A binaries**.

