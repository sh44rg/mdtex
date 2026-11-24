# Distributing mdtex

Run `./build-release.sh` on a Mac with Xcode command-line tools, Node.js and
the project's npm dependencies installed. The resulting disk image is written
to `release/mdtex-<version>-apple-silicon.dmg` (the version comes from Info.plist).
The recipient only needs an Apple silicon Mac running macOS 13 or later; Node
and the source files are not needed. The image includes an Applications link
and installation instructions.

By default, the app is ad-hoc signed and is not notarized. Gatekeeper may block
it when downloaded or received from someone else. The included instructions
explain Apple's manual override. For a normal public release, obtain a Developer
ID Application certificate and configure a notarytool keychain profile, then:

```sh
MDTEX_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
MDTEX_NOTARY_PROFILE='your-notary-profile' ./build-release.sh
```

This signs the app with hardened runtime, signs the disk image, submits it for
notarization, and staples the ticket to the image. The command requires an
available Developer ID certificate and credentials for Apple's notary service.
Providing only the signing identity signs the app and image but does not
notarize them.
