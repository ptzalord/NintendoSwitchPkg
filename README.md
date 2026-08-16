# EDK2 Implementation for Nintendo Switch (Tegra210)

> **Fork of [`imbushuo/NintendoSwitchPkg`](https://github.com/imbushuo/NintendoSwitchPkg)**
> — early research prototype, last upstream activity March 2021.

## Quick-Start (macOS)

```sh
git clone https://github.com/ptzalord/NintendoSwitchPkg.git
cd NintendoSwitchPkg
make docker-build        # requires Docker Desktop or Colima
# Platform is auto-detected from the host architecture:
#   Apple Silicon (arm64)  => linux/arm64
#   Intel Mac (x86_64)     => linux/amd64
# Override: make docker-build PLATFORM=linux/amd64
ls out/                  # TEGRA210_EFI.fd  TEGRA210_EFI.elf  SHA256SUMS
```

See **[DEVELOPMENT.md](DEVELOPMENT.md)** for full build instructions, Colima
setup, dependency pinning details, subsystem status, and the eMMC safety policy.

## Status (upstream, unverified in this fork unless noted)

- Capable of booting Linux EFI-stub images from microSD.
- Windows 10 ARM64 boot manager reached under ACPI (CPU topology only).
- Screen/framebuffer requires Coreboot pre-initialisation.
- UART on right Joy-Con connector (115200 8N1).

## eMMC Safety

**No eMMC write path exists in this repository.**  Generated firmware is
development firmware for non-destructive boot path testing only.
See [DEVELOPMENT.md §7](DEVELOPMENT.md#7-emmc-safety-policy) for the full policy.

## Device Support

See [DEVELOPMENT.md §6](DEVELOPMENT.md#6-subsystem-milestone-matrix) for the
full milestone matrix with verified/unverified/planned status for each subsystem.

## Building

See [DEVELOPMENT.md](DEVELOPMENT.md).

## License

See [LICENSE](LICENSE).

