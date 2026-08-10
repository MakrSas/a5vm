# QEMU backend

A5VM now tracks the iOS-compatible QEMU fork used by UTM as a Git submodule:

- repository: `https://github.com/utmapp/qemu.git`
- branch: `ios-support-v5.1.0`
- pinned commit: `2fb97f4f833a6442d2b62ca6bdbf80b3e386b133`

The fork is kept outside the main repository so the A5VM history remains
small and the exact emulator source is reproducible in GitHub Actions. The
first CI integration target is the `i386-softmmu` system emulator. The
portable A5VM interpreter remains available as a fallback until the QEMU
library is connected to the UIKit display and input callbacks.

## Why this fork

The fork contains the iOS-specific shared-library entry points
(`qemu_init`, `qemu_main_loop`, and `qemu_cleanup`) and the optional iOS JIT
path. On a jailbroken ARMv7 device, the JIT path can use executable code
pages; without that permission the TCG interpreter remains the compatibility
path.

## Integration order

1. Build QEMU with only `i386-softmmu` and the PC devices needed by DOS and
   Windows 95/98.
2. Run QEMU in a dedicated pthread from the iOS 6 frontend.
3. Attach a small display-change listener to copy the QEMU VGA surface into
   `A5VMDisplayView` and forward UIKit keyboard events to QEMU's keyboard
   handler.
4. Package the QEMU library and its license/source notices with the iOS
   artifact.

The repository never stores the user's ISO or floppy images.
