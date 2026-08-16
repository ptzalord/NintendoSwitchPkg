# NintendoSwitchPkg — Development Guide

> **Scope:** Nintendo Switch V1 (HAC-001, Tegra X1 / Tegra210) UEFI firmware  
> **Target OS:** Windows 10 ARM64 (and Linux EFI-stub)  
> **Boot medium:** microSD card (internal eMMC writes are **blocked** — see §7)

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

### Verified facts
- The firmware boots Linux kernel EFI-stub images from microSD.
- Windows 10 ARM64 reaches boot manager stage under ACPI; only CPU topology is
  described in ACPI tables at this point.
- Screen/framebuffer requires Coreboot to set up the display before UEFI
  (see [`imbushuo/Coreboot`](https://github.com/imbushuo/Coreboot)).
- UART output works on the right Joy-Con connector (115200 8N1).

### Assumptions (not yet verified on hardware in this fork)
- The pinned EDK2 tag (`edk2-stable202108`) is compatible with all in-tree
  sources; compiler warnings converted to errors may surface during the first
  build.
- XUSB/EHCI bring-up requires Falcon firmware upload whose legal distribution
  is uncertain; USB will not work until a clean firmware-extraction path is
  confirmed.

---

## 2. macOS Quick-Start

### Prerequisites

| Tool | Install command | Notes |
|------|----------------|-------|
| Docker Desktop | https://www.docker.com/products/docker-desktop/ | Intel or Apple Silicon |
| Colima (alternative) | `brew install colima docker` | Lighter-weight daemon |
| Git | Ships with Xcode CLT | `xcode-select --install` |
| 10 GB free disk | — | For image + build tree |

### Apple Silicon notes

Docker Desktop for Apple Silicon transparently emulates `linux/amd64` containers
via QEMU or Rosetta 2.  Enable **"Use Rosetta for x86/amd64 emulation"** in
Docker Desktop → Settings → Features in development for best build performance.
The `Makefile` auto-detects `arm64` and passes `--platform linux/amd64`.

With Colima:
```sh
colima start --cpu 4 --memory 8 --disk 60 --arch x86_64
```
Use `--arch aarch64` only if you need a native ARM container; the build
toolchain is `amd64` due to pre-built binary availability.

### Build (Docker Desktop or Colima)
```sh
# 1. Clone the fork
git clone https://github.com/ptzalord/NintendoSwitchPkg.git
cd NintendoSwitchPkg

# 2. Validate prerequisites
make check-env

# 3. Build (fetches EDK2, compiles BaseTools, builds firmware)
make docker-build

# 4. Collect artifacts
#    Firmware blobs appear in:  out/
#    SHA-256 checksums printed automatically.
ls out/
```

For an interactive debugging shell inside the container:
```sh
make docker-shell
```

---

## 3. Build Environment Details

### Pinned revisions

| Dependency | Pinned revision | Source |
|---|---|---|
| Ubuntu base image | `22.04` (digest pinned in Dockerfile) | Docker Hub |
| EDK2 | `edk2-stable202108` | tianocore/edk2 |
| gcc-aarch64-linux-gnu | Ubuntu 22.04 APT (11.x) | Ubuntu Jammy |
| acpica-tools (iasl) | Ubuntu 22.04 APT (20211217) | Ubuntu Jammy |

To update a dependency:
1. Change `EDK2_TAG` in `Makefile` and the matching value in
   `.github/workflows/build.yml`.
2. Run `make docker-build` locally and verify no new compiler errors.
3. Update this table.

### Expected artifacts

After a successful build:
```
out/
  NINTENDO_SWITCH.fd      — raw UEFI firmware flash image
  UEFI.elf                — ELF-wrapped image for Coreboot payload loading
  (sha256 printed to stdout)
```

UEFI.elf is required when using the Coreboot-based boot path; NINTENDO_SWITCH.fd
can be booted directly from RCM if a suitable bootloader is configured.

---

## 4. Serial/UART Debugging

**Hardware:** Right Joy-Con connector, 115200 baud, 8-N-1, 3.3 V TTL.

A custom cable or breakout is required.  The UART maps to Tegra210 UART-A
(base address `0x70006000`).

### macOS serial setup
```sh
brew install minicom
minicom -D /dev/cu.usbserial-XXXX -b 115200
# or
screen /dev/cu.usbserial-XXXX 115200
```

### Linux serial setup
```sh
screen /dev/ttyUSB0 115200
# or
picocom -b 115200 /dev/ttyUSB0
```

UEFI debug messages appear immediately at power-on if the `DEBUG` build target
is used.

---

## 5. Windows Kernel-Debug Setup

> **Prerequisite:** Windows 10 ARM64 must already boot to the NT kernel on
> microSD before kernel debugging is useful.  Establish stable UART UEFI output
> first.

### Configure BCD on the Windows ESP partition

Mount the ESP (drive letter `E:` in this example) from a Windows machine and
run:

```cmd
bcdedit /store E:\EFI\Microsoft\Boot\BCD /set {default} debug on
bcdedit /store E:\EFI\Microsoft\Boot\BCD /dbgsettings serial debugport:1 baudrate:115200
```

### Connect WinDbg (Windows host)
1. Open WinDbg → **File → Kernel Debug → COM**.
2. Set baud rate to 115200, select the COM port for your USB-serial adapter.
3. Boot the Switch; WinDbg will break on first contact.

### Connect WinDbg (macOS host via VM)
Run a Windows 10 or 11 x64 VM (UTM/Parallels/VMware Fusion) and pass the
USB-serial adapter through to the VM.  Follow the same BCD and WinDbg steps
above.

### No copyrighted material required
No proprietary Nintendo firmware, console keys, or TSEC/PKA blobs are needed
for the serial kernel debugger path.  The BCD flags above are standard Windows
debugging configuration.

---

## 6. Subsystem Milestone Matrix

Status key: `✅ Working` · `⚠️ Partial` · `🚧 In Progress` · `❌ Not Started` · `🔒 Blocked`

| Subsystem | UEFI Status | Windows Driver Status | Notes |
|---|---|---|---|
| **CPU / GIC** | ✅ Working | ✅ In-box | ACPI MADT, 4-core Cortex-A57 |
| **Arch Timer** | ✅ Working | ✅ In-box | ACPI GTDT |
| **UART / Serial** | ✅ Working | ⚠️ Partial | Debug only; no Windows serial driver |
| **ACPI platform** | ⚠️ Partial | ⚠️ Partial | Only CPU described; all other devices missing |
| **microSD (SDMMC)** | ⚠️ Partial | ❌ Not Started | SDSC/HC boot tested; SDXC less tested; no Windows driver |
| **Framebuffer** | ⚠️ Partial | ❌ Not Started | Requires Coreboot; SimpleFB only; no GPU accel |
| **USB / XUSB (xHCI)** | 🔒 Blocked | ❌ Not Started | Falcon firmware upload needed; tracked in upstream issue #14 |
| **USB / EHCI** | 🚧 In Progress | ❌ Not Started | Partial driver in tree; untested |
| **Touch (I2C HID)** | ❌ Not Started | ❌ Not Started | I2C bus driver exists; HID layer missing |
| **Buttons (sideband)** | ⚠️ Partial | ❌ Not Started | Detected; not registered as EFI input device |
| **eMMC** | 🔒 Blocked | ❌ Not Started | Read-only enumeration next; **no writes** (see §7) |
| **Battery / Charging** | ❌ Not Started | ❌ Not Started | MAX77620 PMIC driver stub present |
| **Thermals** | ❌ Not Started | ❌ Not Started | No ACPI thermal zone |
| **Audio** | ❌ Not Started | ❌ Not Started | ALC5639 codec; I2C + I2S path |
| **Wi-Fi / BT** | ❌ Not Started | ❌ Not Started | Broadcom BCM4356 |
| **Sleep / Resume** | ❌ Not Started | ❌ Not Started | ACPI S3/S4 not described |
| **GPU (Maxwell)** | ❌ Not Started | ❌ Not Started | Requires open or proprietary driver; large project |
| **Dock / USB-C Alt Mode** | ❌ Not Started | ❌ Not Started | Depends on USB host working |
| **Joy-Con (UART HID)** | ❌ Not Started | ❌ Not Started | High-speed serial; low priority |

---

## 7. eMMC Safety Policy

> **This policy is mandatory and enforced by omission — no eMMC write path
> exists in this codebase.**

### Principles

1. **Read-only first.** eMMC support begins with safe enumeration and
   read-only block access only.
2. **No partition-table modification.** The GPT and all Nintendo partition
   entries must be preserved in their original state.
3. **No block writes until all of the following exist and have been reviewed:**
   - Device identification (JEDEC CID/CSD/EXT_CSD read and logged)
   - Capacity and range validation (write requests checked against safe
     partition bounds)
   - Write-protect guards in the driver (software and hardware WP bits)
   - Full verified backup of all Nintendo partitions
   - Tested recovery procedure returning the console to stock boot
4. **Windows installation to internal eMMC is not enabled by this PR.**
   MicroSD is the only Windows boot medium at this stage.
5. **Preserve all existing Nintendo partitions by default.**

### Rationale

A mis-addressed eMMC write at UEFI level can permanently brick the console's
boot chain in a way that is not recoverable without specialized hardware.  The
risk is disproportionate to the benefit at this early stage.

### Future path

When the above criteria are met, eMMC write support will be introduced behind
an explicit `#define EMMC_WRITE_ENABLED` compile-time guard and gated on a
user-visible warning prompt at UEFI runtime.

---

## 8. Log and Artifact Collection

### During a build (CI)
- Artifacts are uploaded by the `upload-artifact` step as
  `NintendoSwitchPkg-firmware-<sha>`.
- SHA-256 checksums are printed to the build log.

### During hardware testing
Collect the following before reporting a hardware bug:

1. **Full UART log** from power-on to failure (capture with `screen -L` or
   `minicom -C log.txt`).
2. **WinDbg !analyze output** if Windows kernel reaches it.
3. **`!devobj` dump** for any unknown device nodes.
4. **Device Manager export** (right-click → Save As from devmgmt.msc).
5. **Event Viewer boot log** (`System`, `Application`, `Microsoft-Windows-Kernel-PnP/Configuration`).
6. **`setupapi.dev.log`** from `%windir%\INF\`.
7. Git commit SHA of the firmware used.

Attach these as a zip to the GitHub issue; do **not** include proprietary keys,
TSEC blobs, or Nintendo firmware files.

---

## 9. Known Limitations and Blockers

| # | Description | Severity | Next action |
|---|---|---|---|
| 1 | ACPI tables only describe CPU; all peripherals invisible to Windows | High | Add ACPI device nodes incrementally per milestone |
| 2 | USB/XUSB blocked on Falcon firmware distribution question | High | Research open-source Falcon firmware or legal extraction |
| 3 | Framebuffer requires Coreboot; no standalone UEFI GOP yet | Medium | Investigate SimpleFB without Coreboot; or document Coreboot build |
| 4 | eMMC driver absent | Medium | Implement read-only SDMMC driver following microSD driver pattern |
| 5 | PowerShell build scripts not portable without pwsh | Low | Pure-bash/Makefile path now primary; PS scripts kept for reference |
| 6 | EDK2 `edk2-stable202108` may have compiler errors with GCC 11 | Unknown | First CI run will surface errors; fix minimal patches inline |

---

## 10. Next Recommended Milestones

### Milestone 1 — Stable build baseline (this PR)
- Reproducible Docker build on macOS (Intel and Apple Silicon)
- CI on every PR
- UART output confirmed

### Milestone 2 — USB/XUSB host
Prerequisite: resolve Falcon firmware distribution question.  
Goal: keyboard and USB-storage working in UEFI shell.

### Milestone 3 — ACPI expansion
Add ACPI device nodes for SD/storage, GPIO, I2C, and interrupt routing so
Windows PnP can enumerate hardware.

### Milestone 4 — eMMC read-only
Safe read-only eMMC enumeration following the policy in §7.

### Milestone 5 — Windows full boot
Windows 10 ARM64 desktop from microSD with at minimum: display, USB HID,
storage, and network/debug path.

---

*This document reflects the state as of the initial baseline PR.  Sections
marked "Assumption" or "Not yet verified" should be updated as hardware testing
progresses.*
