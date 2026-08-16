# NintendoSwitchPkg — Development Guide

> **Scope:** Nintendo Switch V1 (HAC-001, Tegra X1 / Tegra210) UEFI firmware
> **Target OS:** Windows 10 ARM64 (long-term goal) and Linux EFI-stub
> **Boot medium:** microSD card (internal eMMC writes are **blocked** — see §7)

---

## Claim classification used throughout this document

| Label | Meaning |
|---|---|
| ✅ **Verified upstream** | Reported in imbushuo/NintendoSwitchPkg issues, commits, or README |
| 🔬 **Unverified in this fork** | Not tested in this fork; treat as assumption until hardware evidence is provided |
| 🚧 **Future work** | Not yet implemented; documented as a planned milestone |

---

## Table of Contents

1. [Repository Overview](#1-repository-overview)
2. [macOS Quick-Start](#2-macos-quick-start)
3. [Build Environment Details](#3-build-environment-details)
4. [Serial/UART Debugging](#4-serialuart-debugging)
5. [Windows Kernel-Debug Setup](#5-windows-kernel-debug-setup)
6. [Subsystem Milestone Matrix](#6-subsystem-milestone-matrix)
7. [eMMC Safety Policy](#7-emmc-safety-policy)
8. [Log and Artifact Collection](#8-log-and-artifact-collection)
9. [Known Limitations and Blockers](#9-known-limitations-and-blockers)
10. [Next Recommended Milestones](#10-next-recommended-milestones)

---

## 1. Repository Overview

This is a fork of [`imbushuo/NintendoSwitchPkg`](https://github.com/imbushuo/NintendoSwitchPkg),
an EDK2 platform package for the Nintendo Switch V1.  The project is an **early
research prototype**; last upstream activity was March 2021.

### What this fork adds (this PR)

- A reproducible Docker build path for macOS (Docker Desktop or Colima).
- Shared build scripts (`scripts/`) used by both Docker and GitHub Actions CI.
- Corrected Dockerfile and CI workflow (see §3 for blockers fixed vs PR #1).
- This development guide with accurate claim classification.

### Upstream facts (✅ Verified upstream)

- ✅ The firmware can boot Linux kernel EFI-stub images from microSD
  (upstream README, March 2021).
- ✅ Windows 10 ARM64 boot manager stage is reached under ACPI;
  only CPU topology is described at this point (upstream README).
- ✅ Screen/framebuffer requires Coreboot to initialise the display before UEFI
  (upstream README; see [`imbushuo/Coreboot`](https://github.com/imbushuo/Coreboot)).
- ✅ UART is present on the right Joy-Con connector (upstream README: 115200 8N1).

### Hardware assumptions (🔬 Unverified in this fork)

The following statements appear in upstream documentation or source comments
but have **not been independently verified** in this fork or on a physical
device by this author:

- 🔬 Tegra210 UART is controller `8250/16550-compatible` at the address used
  in `Library/Tegra8250SerialPortLib/`.  Source: upstream code; not re-tested here.
- 🔬 GIC base addresses in `AcpiTables/Madt.aslc` match the physical hardware.
  Source: upstream code; SoC TRM reference would be required for independent validation.
- 🔬 The eMMC controller is accessible via the `SdMmcDxe` driver path.
  Source: upstream README ("eMMC support will be added soon").  No write implementation exists.
- 🔬 Joy-Con UART is usable without the physical dock.  Source: upstream README.

---

## 2. macOS Quick-Start

### Prerequisites

| Requirement | Notes |
|---|---|
| Docker Desktop ≥ 4.x **or** Colima ≥ 0.5 | Colima is a lighter alternative |
| ≥ 10 GB free disk space | EDK2 source + build output |
| Xcode Command Line Tools | Provides `make` |

### Docker Desktop (recommended)

```sh
# 1. Clone the repository
git clone https://github.com/ptzalord/NintendoSwitchPkg.git
cd NintendoSwitchPkg

# 2. Build (Apple Silicon — native linux/arm64)
make docker-build

# 3. Retrieve artifacts from out/
ls out/
cat out/SHA256SUMS
```

### Colima (Apple Silicon)

```sh
# Start Colima with ARM64 support
colima start --arch aarch64 --cpu 4 --memory 8

# Then build as usual
make docker-build
```

### Intel Mac or forcing amd64

If you need `linux/amd64` (e.g. an amd64-specific dependency is confirmed in
future work), pass:

```sh
make docker-build PLATFORM=linux/amd64
```

> **Note:** amd64 emulation on Apple Silicon requires Rosetta 2 to be enabled
> in Docker Desktop preferences ("Use Rosetta for x86/amd64 emulation").
> Native `linux/arm64` is preferred and is the default.

### Platform support note

The build container itself targets AArch64 cross-compilation for the firmware
regardless of host architecture.  Both `linux/amd64` and `linux/arm64` host
images should produce identical firmware `.fd` output because the compiler
(`gcc-aarch64-linux-gnu`) targets the same output architecture.

---

## 3. Build Environment Details

### Dependency pinning

| Component | Pinned to | Immutable? |
|---|---|---|
| Ubuntu base image | `ubuntu:22.04@sha256:149d67e29f765f4db62aa52161009e99e389544e25a8f43c8c89d4a445a7ca37` | ✅ digest-pinned |
| EDK2 | commit `ba91d0292e593df8528b66f99c1b0b14fadc8e16` (tag `edk2-stable202108`) | ✅ commit-pinned |
| APT packages | Ubuntu 22.04 repo versions at image-build time | ⚠️ **Not independently pinned** |

**APT package version limitation:** `gcc-aarch64-linux-gnu`, `acpica-tools`,
`nasm`, `uuid-dev`, and other APT packages are installed from Ubuntu 22.04
repositories without explicit version pins.  Ubuntu 22.04 LTS repositories
are stable (packages rarely change except for security updates), but this is
not a total reproducibility guarantee.  A future improvement would lock each
package to a specific `.deb` version.

### Packages installed

```
build-essential  gcc-aarch64-linux-gnu  binutils-aarch64-linux-gnu
python3  python3-distutils  acpica-tools  uuid-dev  nasm
make  bison  flex  libssl-dev
```

`acpica-tools` provides the `iasl` ACPI compiler.  There is no separate `iasl`
package on Ubuntu 22.04.

PowerShell is **not** installed in the container.  The upstream
`Tools/edk2-build.ps1` script is present in the repository for reference but
is not invoked by the shared build scripts.

### Shared build scripts

All build logic lives in `scripts/` and is invoked identically by Docker and CI:

| Script | Purpose |
|---|---|
| `scripts/fetch-deps.sh` | Clone EDK2 at the pinned commit SHA and initialise submodules |
| `scripts/build.sh` | Write `Include/FwReleaseInfo.h`, build BaseTools, build firmware |
| `scripts/collect-artifacts.sh` | ELF-wrap `.fd` files, collect to `out/`, generate `SHA256SUMS` |

### Corrections from PR #1

| Blocker | Status |
|---|---|
| Inline shell comments inside apt-get backslash continuation | ✅ Fixed |
| `iasl` APT package (does not exist separately) | ✅ Removed; `acpica-tools` used |
| `FwReleaseInfo.h` written to `NintendoSwitchPkg/Include/…` (wrong path) | ✅ Fixed; written to `Include/FwReleaseInfo.h` relative to WORKSPACE |
| CI and Docker using independent build implementations | ✅ Fixed; both call shared `scripts/` |
| Docker path not generating `UEFI.elf` | ✅ Fixed; `collect-artifacts.sh` called in both paths |
| Artifact steps succeeding when outputs absent | ✅ Fixed; scripts exit non-zero when `.fd`/`.elf` are missing |
| Unverified hardware claims written as facts | ✅ Addressed; claims labelled per §1 |

---

## 4. Serial/UART Debugging

🔬 **Unverified in this fork** — the following is based on upstream
documentation and has not been independently re-tested.

- **Connector:** right Joy-Con rail connector (hardware UART)
- **Settings:** 115200 baud, 8 data bits, no parity, 1 stop bit (8N1)
- **Level:** 3.3 V logic level; use a 3.3 V compatible USB-UART adapter
- **Pins:** TX/RX/GND on the Joy-Con connector PCB pads
  (refer to community teardown documentation for exact pad locations)

For development, attach a USB-UART adapter and open a serial terminal before
powering the device.

---

## 5. Windows Kernel-Debug Setup

🔬 **Unverified in this fork** — the following reproduces the upstream README
setup commands.  Functionality depends on UART being operational (§4).

On the Windows boot volume (after Windows installation — a future milestone):

```bat
bcdedit /store E:\EFI\Microsoft\Boot\BCD /set {default} debug on
bcdedit /store E:\EFI\Microsoft\Boot\BCD /dbgsettings serial debugport:1 baudrate:115200
```

Then attach WinDbg on the host PC using a serial connection to the Joy-Con UART.

---

## 6. Subsystem Milestone Matrix

Status column meanings:
- **Working** — ✅ Verified upstream
- **Partial** — 🔬 Partially implemented; unverified in this fork
- **Blocked** — Known blocker; see §9
- **Planned** — 🚧 Future work; not yet implemented

| # | Subsystem | Status | Notes |
|---|---|---|---|
| 1 | CPU / GIC / Arch Timer | Working | ✅ Upstream; ACPI MADT and GTDT present |
| 2 | UART | Partial | 🔬 Code present; hardware untested in this fork |
| 3 | Display / Framebuffer | Partial | 🔬 Requires Coreboot pre-init; driver present |
| 4 | microSD | Partial | ✅ Upstream reports SDSC/HC working; XC probed |
| 5 | eMMC | Blocked | See §7; read-only enumeration is a future milestone |
| 6 | Clock management | Partial | 🔬 Driver present; unverified in this fork |
| 7 | Power management (PMC/PMIC) | Partial | 🔬 Driver present; unverified in this fork |
| 8 | GPIO / Pin Mux | Partial | 🔬 Driver present; unverified in this fork |
| 9 | USB EHCI | Blocked | Partially implemented; see §9 |
| 10 | USB XUSB/xHCI | Blocked | Requires Falcon firmware; see §9 |
| 11 | Touchscreen | Planned | 🚧 No driver |
| 12 | Buttons (sideband) | Partial | 🔬 Driver present; not registered as EFI input |
| 13 | Battery / charging | Planned | 🚧 No driver |
| 14 | Thermal management | Planned | 🚧 No driver |
| 15 | Audio | Planned | 🚧 No driver |
| 16 | Wi-Fi / Bluetooth | Planned | 🚧 No driver |
| 17 | GPU (accelerated) | Planned | 🚧 Separate major project |

---

## 7. eMMC Safety Policy

> **Policy: no eMMC write operations in this PR or any derived work until all
> conditions below are met.**

The Nintendo Switch internal eMMC contains the device's factory firmware,
cryptographic keys, and operating system.  A failed or misdirected write can
leave the console unable to boot its stock firmware with no straightforward
recovery path.

### Current state

- **No eMMC write path exists** in this codebase.
- The `SdMmcDxe` driver handles microSD; eMMC enumeration is noted as a future
  goal in the upstream README but is not implemented.
- Generated firmware artifacts are **development firmware** that must first be
  tested through a **recoverable, non-destructive boot path** (e.g., a payload
  chain-loader from a microSD card) before any internal storage is involved.

### Requirements before any eMMC write is considered

All of the following must be implemented, reviewed, and tested before eMMC
write support can be added:

1. ✅ Reliable read-only eMMC device enumeration.
2. Hardware device identity verification (correct eMMC device confirmed).
3. Explicit write-enable guard (write path disabled by default).
4. Partition-range bounds checks (writes restricted to explicitly allocated regions).
5. Verified full eMMC backup procedure and recovery test.
6. Separate reviewed PR dedicated solely to eMMC write support.

### What must never be done (in this and future PRs)

- No partition-table changes to eMMC partitions.
- No block-write path to eMMC.
- No Windows-to-eMMC deployment or installation automation.
- No instructions to erase, reformat, or repartition eMMC.

---

## 8. Log and Artifact Collection

After a successful build the following files are present in `out/`:

| File | Description |
|---|---|
| `TEGRA210_EFI.fd` | Raw firmware image |
| `TEGRA210_EFI.elf` | ELF-wrapped firmware (for payloads that prefer ELF) |
| `SHA256SUMS` | SHA-256 checksums of both files |

To reproduce checksums locally:

```sh
make docker-build
sha256sum -c out/SHA256SUMS
```

---

## 9. Known Limitations and Blockers

### USB EHCI / XUSB

- `Drivers/EhciPciEmulationDxe/` provides a PCI emulation layer for the EHCI
  controller but is incomplete.
- The Tegra XUSB (xHCI) controller requires a Falcon microcontroller firmware
  blob (`xusb_sram.bin`) for proper initialisation.  This blob is proprietary
  and cannot be distributed in this repository.
  Upstream tracking issue: [`imbushuo/NintendoSwitchPkg#14`](https://github.com/imbushuo/NintendoSwitchPkg/issues/14).

### ACPI tables

- Current ACPI tables describe only CPU topology (MADT, GTDT) and a debug
  serial port (DBG2).  Storage, USB, GPIO, and other devices are absent.

### Display

- 🔬 The `SimpleFbDxe` driver assumes the display framebuffer is already
  initialised by Coreboot.  Without the Coreboot chain, the display may remain
  blank.

---

## 10. Next Recommended Milestones

In priority order after this build baseline is verified:

1. **Hardware boot test** — boot the generated `.fd` on physical hardware via
   microSD payload; confirm UART output.
2. **Read-only eMMC enumeration** — detect and identify the eMMC device without
   writes.
3. **USB EHCI stabilisation** — complete the EHCI driver for USB keyboard/storage.
4. **ACPI expansion** — add USB, GPIO, I2C, and storage device descriptions.
5. **XUSB/xHCI** — upstream Falcon firmware distribution blocker must be
   resolved before proceeding.
