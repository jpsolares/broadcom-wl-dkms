# broadcom-wl-dkms (kernel 7.x compat fork)

This is the AUR [`broadcom-wl-dkms`](https://aur.archlinux.org/packages/broadcom-wl-dkms)
package (Broadcom's proprietary `wl` STA driver) with extra patches that get
it building and working again on modern (7.x-era) Linux kernels.

Basado en / Based on: https://github.com/nzarg/broadcom-wl-dkms

Extra patches in this fork:

- `099-kernel-7.0-compat.patch` (kernel 7.0+ compatibility base)
- `100-kernel-7.1-compat.patch` (additional kernel 7.1+ fixes)

Target / probado con: Broadcom BCM4360 (PCI ID `14e4:43a0`, Apple subsystem `106b:0134`).

## Who needs this

You have a Broadcom **BCM4360** 802.11ac chip (notably the one in 2013-2015
MacBook/MacBook Pro Retina models — PCI ID `14e4:43a0`, Apple subsystem
`106b:0134`) and:

- The open-source `brcmsmac` driver loads but never binds — your chip's core
  revision (`0x2A`) isn't in its supported list.
- `brcmfmac` doesn't apply either — this is a softmac PCIe chip, not the
  fullmac USB/SDIO variant `brcmfmac` targets.
- The stock AUR `broadcom-wl-dkms` package fails to build with errors like
  `fatal error: net/lib80211.h: No such file or directory`, or later,
  undefined `wlc_*` symbols, or an `objtool: ... unannotated intra-function
  call` error.

This package fixes all of that.

## What was actually broken

The upstream driver (Broadcom's last release, 2015) was never updated past
kernel 4.8-era compatibility. By kernel 7.x, on top of that:

- `net/lib80211.h` was removed from the kernel entirely. The driver only
  used it for one struct tag (`lib80211_crypto_ops`) and never linked
  against the real subsystem, so the fix vendors the last public copy of
  the header instead of trying to depend on a removed kernel facility.
- The PCI DMA API (`pci_alloc_consistent`, `pci_map_single`,
  `PCI_DMA_TODEVICE`, ...) was replaced by the generic `dma_*` API years
  ago.
- `set_fs()`/`get_fs()` — used to fake a "kernel-space" context for an
  internal ioctl-bridging call — was removed outright. The internal
  cfg80211-to-legacy-ioctl bridge (`wl_dev_ioctl`) now bypasses the
  userspace-copy path entirely via a new `wl_ioctl_kernel()` that calls
  `wlc_ioctl()` directly; real userspace ioctls (`iwconfig` etc.) are
  unaffected.
- The old timer API (`init_timer`, `timer.data`/`.function`) was replaced
  by `timer_setup()`/`timer_container_of()`/`timer_delete()`.
- `/proc` file operations now use `struct proc_ops` instead of
  `struct file_operations`.
- Several `cfg80211_ops` callback signatures gained new parameters
  (`radio_idx`, `link_id`) for multi-link/multi-radio support that didn't
  exist when this driver was written.
- `cfg80211_roamed()` and `ioremap_nocache()`/`PDE_DATA()` etc. all changed
  shape or were renamed.
- The kernel's `Makefile.build` dropped `EXTRA_CFLAGS`/`EXTRA_LDFLAGS`
  entirely in favor of `ccflags-y`/`ldflags-y` — without this rename the
  module silently lost both its include paths *and* the link against
  Broadcom's shipped binary blob (`wlc_hybrid.o_shipped`), which is the
  only place the actual 802.11 MAC/PHY logic lives (no source available).
- `objtool` (IBT/CFI validation) rejects that same 2015-era blob outright
  since it predates the annotations entirely. There's no source to fix, so
  `dkms.conf`'s `MAKE[0]` override runs the build with `objtool=/bin/true`
  for this module only — it does not touch IBT/CFI enforcement anywhere
  else on the system.

Most of the above is in `099-kernel-7.0-compat.patch`, applied after the
AUR package's existing patches 001-005 (which already cover some
kernel-4.7/4.8-era and IEEE80211_BAND→NL80211_BAND renames — 099 was
written against that baseline and doesn't duplicate them).

Additional 7.1-era API fixes are in `100-kernel-7.1-compat.patch`:

- Replace `bcopy()` writes to `dev->dev_addr` with `dev_addr_set()`.
- For kernels 7.0+, wrap the `cfg80211_ops` callbacks that now take a
  `struct wireless_dev *` so the driver can continue to use its existing
  `struct net_device *` implementations.

## Installing

```sh
makepkg -si
```

Standard `PKGBUILD` build. Pulls Broadcom's source tarball, applies all seven
patches via DKMS, builds against your running kernel, and installs.

Pop!_OS / Ubuntu (XanMod) helper script:

The Broadcom tarball (`hybrid-v35_64-nodebug-pcoem-6_30_223_271.tar.gz`) is required.
Download it first (recommended):

```sh
wget -nc https://docs.broadcom.com/docs-and-downloads/docs/atheros/hybrid-v35_64-nodebug-pcoem-6_30_223_271.tar.gz
```

Then run:

```sh
sudo ./install-popos-xanmod.sh
```

After install, blacklist the in-tree drivers that would otherwise fight
`wl` for the device (skip any line for a driver you don't have loaded):

```sh
# /etc/modprobe.d/broadcom-wl-blacklist.conf
blacklist b43
blacklist b43legacy
blacklist brcm80211
blacklist brcmfmac
```

Then `modprobe wl` (or reboot). DKMS will automatically rebuild the module
against future kernel updates, patches and all.

## Caveats

- There's a benign `memcpy: detected field-spanning write ... at
  wl_cfg80211_hybrid.c:3017` warning in `dmesg` during scans — it's
  fortify-source flagging an old C89 zero-length-array-as-flexible-array
  idiom in `wl_cp_ie()`. The function already bounds-checks
  (`ie->offset > dst_size`) before the copy; this has been confirmed
  working in practice (verified scan + WPA2 connect + working internet
  access) despite the warning.
- This is still Broadcom's unmaintained, proprietary driver. Treat it as
  a last resort if `brcmsmac`/`brcmfmac` genuinely don't support your
  chip revision — check `cat /sys/bus/bcma/devices/*/rev` against
  `modinfo brcmsmac | grep alias` first.
