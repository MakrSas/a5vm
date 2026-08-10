# VM OS presets

This is the planned UTM-like creation flow for A5VM. A user should not have to
know which virtual hardware is required by an operating system.

## Creation flow

```text
New Machine
    -> choose OS family
    -> choose OS version
    -> A5VM selects a compatible machine profile
    -> user selects an installation image
    -> review configuration
    -> create VM
```

The application owns the configuration. The user supplies the installation
media that they are legally allowed to use.

## Preset families

### DOS

Initial versions:

- MS-DOS 3.x / 5.x / 6.x
- FreeDOS

Suggested defaults:

- IBM PC/XT or PC/AT profile
- 8086/80286 CPU for the first MVP
- 640 KB or 1 MB RAM
- VGA text mode
- floppy `IMG` as the boot medium

### Windows

Initial versions:

- Windows 3.1
- Windows 95
- Windows 98

Suggested defaults:

- 386 or 486 PC profile
- protected-mode x86 CPU
- configurable RAM selected by the version
- VGA and IDE disk
- bootable floppy, hard-disk image, or installation ISO depending on the release

### MacOS

For the classic Macintosh line, the UI may display this family as “Mac OS”
while keeping the product preset name “MacOS”.

Initial versions:

- System 6 / System 7
- Mac OS 8 / 9
- later PowerPC experiments as a separate advanced preset

Suggested defaults:

- 68k Macintosh profile for System 6/7/early Mac OS
- Power Macintosh profile for Mac OS 8/9
- user-provided ROM plus disk image when the selected system requires it

## Preset data model

Each preset should resolve to a normal VM profile instead of containing special
logic in the emulator core:

```text
osFamily       = dos | windows | macos
osVersion      = user-selected version
machineProfile = ibm-pc-xt | ibm-pc-at | i386-pc | mac-68k | power-mac
cpu            = selected CPU backend and mode
ramBytes       = preset default, user-adjustable where safe
devices        = VGA, floppy, IDE, keyboard, etc.
firmware       = BIOS or Macintosh ROM requirement
bootOrder      = floppy | cdrom | disk
mediaType      = img | iso | rom | disk
mediaPath      = user-selected file in app storage
```

The selected version chooses the initial values automatically, but the final
configuration remains editable from the VM settings screen.

## UI screens

The iOS 6 implementation should use old-style UIKit controllers compatible with
the current app:

1. `New Machine` — OS family cards: DOS, Windows, MacOS.
2. `Choose Version` — versions available for the selected family.
3. `Configuration` — generated CPU/RAM/devices with optional overrides.
4. `Installation Media` — choose or import `IMG`, `ISO`, `ROM`, or disk image.
5. `Create VM` — save the resulting profile to the Machines library.

No operating-system images or copyrighted ROMs belong in this repository.

## Implementation order

1. Add the profile schema and migration for existing 8086 machines.
2. Add DOS presets that produce the current floppy-based 8086 profile.
3. Add a file/media picker for user-provided `IMG` files.
4. Add Windows profiles after 386/protected mode and IDE support exist.
5. Add Mac OS profiles after 68k or PowerPC CPU and Macintosh ROM support exist.

## Current implementation status

The current DOS profile is runnable on the 8086 machine backend. The portable
core also contains an initial `cpu386` backend that can execute a real-mode
setup sequence through `LGDT`, `CR0.PE`, and a protected-mode far jump, plus a
small 32-bit instruction subset. IDE PIO and the virtual hard disk are already
available to the 8086 machine.

The Windows presets remain marked as unavailable until the 386 backend is
connected to the machine's BIOS, interrupt, and media boot path. MacOS presets
still require a separate Macintosh CPU/ROM backend.
