# Audio Units and Logic Pro Content on an External Volume

Split from [external-storage.md](external-storage.md), which holds the method for
each claim in [How Each Claim Was Checked](external-storage.md#how-each-claim-was-checked).

## Audio Units Cannot Live on an External Volume

Apple's Audio Toolbox documentation for
[Audio Components](https://developer.apple.com/documentation/audiotoolbox/audio-components)
states that the system searches for `.audiocomp` and `.component` bundles in
exactly three locations:

- `~/Library/Audio/Plug-Ins/Components`
- `/Library/Audio/Plug-Ins/Components`
- `/System/Library/Components`

All three are on the boot volume, and no API adds a search path;
`AudioComponentRegister` registers a component in the calling process only. So
an Audio Unit v2 `.component` bundle has to sit in one of those three
directories. An Audio Unit v3 plug-in is delivered as an app extension inside an
application, so its location is wherever that application is installed.

What you can move is the sample content, which each vendor's installer usually
lets you place. Apple's support page
[Where are third-party Audio Units plug-ins installed on Mac?](https://support.apple.com/en-us/102239)
lists the first two directories and says nothing about external volumes.

## Logic Pro and MainStage Content

From Apple's support page
[Move Logic Pro for Mac and MainStage content](https://support.apple.com/en-us/111094):

- **Logic Pro 12 or MainStage 4 or later.** "In the Music folder on your Mac,
  locate the file called "Logic Pro Library.bundle."" Move that bundle to the
  external drive.
- **Logic Pro 11.2.2 or MainStage 3.7.1 or earlier.** Choose "Logic Pro >
  Sound Library > Relocate Sound Library".

The page's own requirements, quoted:

- "You can't store the Sound Library on a volume used for Time Machine backups."
- "Don't rename the storage device or volume after you've moved the Sound
  Lbrary." The misspelling is Apple's.
- "If you have more than one Mac running Logic Pro or MainStage, each Mac needs
  its own Sound Library."
- "Make sure to click Allow when Logic Pro or MainStage asks for permission to
  access the external device."

The page also covers formatting a drive that "isn't formatted for use with Mac",
enabling Removable Volumes under Privacy & Security > Files and Folders if
relocation is refused, and moving the library back.

**Apple Loops are not part of the move.** The Logic Pro 10.4 user guide page
[Manage Logic Pro content](https://help.apple.com/logicpro/mac/10.4/en.lproj/lgcpf77e757d.html)
states that "When you relocate the Sound Library, all Sound Library content
except for Apple Loops and Impulse Responses" "is moved to the new location."
The current support page says nothing about Apple Loops, and Apple documents no
supported way to put them on an external drive. Symlinking them is a user
practice found in Apple Community threads, not a supported configuration.
