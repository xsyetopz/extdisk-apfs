# The Startup Line That Attaches the Simulator Image

How `extdisk-apfs simdisk` re-attaches the disk image in each new shell, and why
it is a line in the shell startup file and not a LaunchAgent. Measured on macOS
27.2 with Xcode 27.1. The image and the mount are described in
[simulator-disk-image.md](simulator-disk-image.md), and the refusal that makes the
image necessary in [simulator-storage.md](simulator-storage.md).

## Why Not a LaunchAgent

A LaunchAgent that was tried could not attach an image on the external volume or
read a file on it, and the cause is not identified. One diagnostic agent wrote
its results to a log:

```text
A: image on the BOOT volume
/dev/disk9s1	Apple_APFS_Volume    	/private/tmp/bootimg/mp
exit=0
B: image on the EXTERNAL volume
Error: The operation couldn't be completed. Operation not permitted
exit=1
C: plain read of a file on the external volume
UNREADABLE
```

What was measured: from the agent the attach failed with `Operation not
permitted` and a plain read of a file on the volume failed, while the same agent
attached a boot-volume image with exit 0. The interactive shell that succeeds at
both does not have Full Disk Access: reading
`~/Library/Application Support/com.apple.TCC/TCC.db`, which needs it, failed.
This is consistent with the removable-volume restriction, and no grant was tried
for the agent, so the mechanism is still not identified. It is one run of one
agent, and it fits the refusal that [simulator-storage.md](simulator-storage.md)
records for `CoreSimulatorService` without proving that they share a cause.

## The Line

`simdisk` adds one line to the shell startup file (`~/.zshenv` for zsh,
`~/.bash_profile` for bash), in a marked block keyed `simulator <volume>`. The
key is separate from the `<volume>` block that `host` writes, so each replaces
and removes on its own. The word goes first because a mount point always starts
with a slash, so no volume name can equal another volume's key; the order
`<volume> simulator` collided with a volume named `/Volumes/Foo simulator`. The
installed line on this machine:

```sh
[ -d /Volumes/DevAudioStore/SimDevices.sparsebundle ] && ! /sbin/mount | /usr/bin/grep -qF \ on\ /Users/krystian/Library/Developer/CoreSimulator/Devices\ \( && /usr/sbin/diskutil image attach --mountPoint /Users/krystian/Library/Developer/CoreSimulator/Devices /Volumes/DevAudioStore/SimDevices.sparsebundle >/dev/null 2>&1 || true
```

Every path is quoted with `shell_quote`, so a volume named with a space, a `$` or
a backtick is not expanded by the shells that read the file. The line ends in
`|| true` and discards all output, so it never fails or prints in a shell.

## What Was Measured

- A fresh `zsh -l -c true` after `diskutil eject` attached the image, and
  `simctl list devices available` then showed the image's own devices: `iPhone 17`
  as `066B909E-C685-4ED8-9F23-82BD477AE7F0` and `iPad (A16)` as
  `972CD7D7-75E0-4F47-AB04-C82D3AD428ED`.
- The line is silent and exits 0 under both `/bin/sh` and `/bin/zsh`, whether
  the image is already attached or the drive is absent.
- Attaching the same image at the same mount point again is a no-op: the mount
  count stayed 1, and two concurrent attaches also left 1. That covers only the
  same image at the same point. A second volume's block that names the same set
  path stacks a mount and hides the first, also measured, and the `mount` test in
  the line is what stops it. It costs one `mount` call per shell.
- `diskutil image attach --mountPoint` ignores the mount point for an image that
  is already attached. A scratch image attached at `/private/tmp/elsewhere/a`,
  then attached with `--mountPoint /private/tmp/elsewhere/b`, printed
  `/private/tmp/elsewhere/a` and exited 0, and `mount` showed one mount. With the
  live image attached at `/private/tmp/elsewhere-mp`,
  `simdisk /Volumes/DevAudioStore` exited 1 with `is already attached at
  /private/tmp/elsewhere-mp, not at ...; eject it first`.
- A second `simdisk` run made no new `.extdisk-backup` file: it printed `skipped:
  the block in /Users/krystian/.zshenv is already this`, and the backup count
  stayed at 2.
- `simdisk /Volumes/GoneDrive --undo` exited 0 and reported both steps skipped,
  and `simdisk / --undo` exited 1 with `/ is on the boot volume`.
- `simdisk --undo` removed only the `simulator` block and left `host`'s block at
  lines 2 to 8 of `~/.zshenv` untouched. A second `--undo` reported both steps
  skipped. The real `simdisk` run and the real `--undo` both worked, including
  the `diskutil eject`.
- The foreign-mount refusal works against a real second image: `error: ...
  already has /dev/disk9s1 mounted on it, which is not ...; eject it first`,
  exit 1, and the mount count stayed 1.
- The symlink refusal works: exit 1, with the message naming the link target.
- `xcrun xctrace list devices`, which is Xcode's own tooling and not `simctl`,
  lists the simulators with the image's UUIDs. That is the evidence that Xcode
  reads the mounted set. There is no `Simulator.app` on this machine; Xcode 27.1
  runs the simulator UI through `SimulatorTrampoline.xpc` inside
  `CoreSimulator.framework`.

## When the Line Does Not Fire

The line runs only when a shell starts. If Xcode is launched from the Dock or
Finder before any shell has run since the drive was plugged in, nothing has
attached the image, and Xcode uses the device set on the internal disk. Open a
terminal first, or run `diskutil image attach` by hand. That follows from where
the line lives; no launch from the Dock was run to observe it.

## Not Tested

If Xcode is already running against the internal set when the image is mounted
over it, `CoreSimulatorService` may still hold the old directory. This was not
tested, and neither outcome is claimed. Quit Xcode before the first mount.

## Undoing It

`--undo` removes the `simulator <volume>` block, then ejects the mount point if
the image is mounted there, and skips with a reason otherwise. The directory that
the mount shadowed is visible again after a successful eject. It leaves
`SimDevices.sparsebundle` in place and says where. Removing that file destroys
the devices inside it, and the tool never does that.

Undo does not need the drive to be plugged in, because that is when a user wants
the line gone. It checks only that the path is absolute and that the volume is not
the boot volume. A refused eject, because the image is busy, is a warning with the
command to run after quitting Xcode, and the result says the image is still
mounted, so the directory it covers is still hidden.

### A Booted Simulator Stops the Eject

`simdisk_booted` lists the UDID of each booted simulator, from `xcrun simctl list
devices booted`. When the image is mounted at the device set (state `ours`) and
any simulator is booted, `--undo` dies before it changes anything. It tells you
to run `xcrun simctl shutdown all` and try again. The check comes before the
startup line is removed, so a refusal cannot leave the line gone and the image
still mounted.

Nothing booted and "could not ask" are different answers, and the exit status is
what separates them. Without `xcrun` on `PATH` there is no simulator to be
booted, so the eject goes ahead. When `simctl` runs but fails, which is the case
that actually happens because `/usr/bin/xcrun` is a shim present on practically
every Mac, `--undo` warns that it could not check and carries on, because undo
has to work on a Mac with no usable Xcode and because the eject itself fails
safely when something holds the mount. The earlier shape of this function made
that a silent exit: under `set -euo pipefail` a non-zero status from it in a
bare assignment ended the run before the startup line was touched. Measured with
a stand-in `xcrun` exiting 72, the script ended at the assignment and printed
nothing. `tests/run-simdisk` now covers it end to end through `bin/extdisk-apfs`,
which is the only place `set -e` is in force.

The reason for the refusal is open handles. With one simulator booted, `lsof`
counted 227 open handles on the mounted device set. After
`xcrun simctl shutdown all` it counted 0. That a held mount is what makes macOS
report a drive as not ejected properly is the reading of that count and is not
separately observed.

One eject done while the image was in use cost this. `diskutil verifyVolume`
reported `The volume /dev/rdisk5s1 ... appears to be OK` and `The container
/dev/rdisk5 appears to be OK`, exit code 0, and the same for the volume inside
the image, so no file system damage was found. `CoreSimulator` then rebuilt the
device set: the image's 11 stock device folders were replaced by 11 fresh ones.
How those were counted was not recorded, so take the number as approximate. It
is one observed case and not a rule for what a bad eject does.

### Eject the Image before Unplugging the Drive

While the image is attached, the drive cannot be ejected. An eject of
`/Volumes/DevAudioStore` requested with `SimDevices.sparsebundle` on it mounted
at the device set failed, and `diskarbitrationd` logged `unmount call ...
returned (status code 0x00000010)`, which is `EBUSY`. macOS then showed its
`Disk Not Ejected Properly` notification. The volume verified clean afterwards
(`diskutil verifyVolume`, exit code 0). Which process asked for the eject is not
in the log, because `diskarbitrationd` redacts its client.

So `extdisk-apfs simdisk <volume> --undo` is the step before unplugging: it
ejects the image, after which the drive ejects normally. `diskutil eject
<volume>` on its own does not reach the image.

`extdisk-apfs unhost` leaves the `simulator <volume>` block alone, because it
removes only what `host` wrote. `simdisk --undo` is what removes it.

## What a Failed Run Leaves

The checks on the device set path run before anything is created, so a refusal
leaves nothing. Past them, a failure leaves what was already made. A newly
created `SimDevices.sparsebundle` on the volume and a newly created
`~/Library/Developer/CoreSimulator/Devices` stay if the attach then fails.
Running `simdisk` again is idempotent: it skips an image that exists and a
directory that exists. `--undo` removes neither. Look for the image at
`<volume>/SimDevices.sparsebundle` and for the directory at the device set path;
an empty one is safe to remove by hand, and the image is yours to remove only if
nothing you want is inside it. If the startup file cannot be named from `$SHELL`,
the attach has already happened, so the run warns, prints the line to add, and
exits 0.
