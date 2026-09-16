# phantom

<p align="center">
  <img src="docs/phantom-mark.png" alt="Phantom" width="180">
</p>

spoof your location and movements.

Phantom is a macOS app that sets your iPhone's or iPad's GPS location to wherever you click on a map. It works over a USB cable, and it doesn't need root or a jailbreak.

## What you need

- **A Mac** running macOS 14 or later with the Xcode Command Line Tools. Full Xcode isn't needed.
- **An iPhone or iPad** and a cable. Wi-Fi-only iPads work too, since the location is injected in software.
- **Internet access** the first time, for the Python components and for the developer disk image that Apple signs per device.

## Setup, start to finish

Five steps, about five minutes. Run them in order.

**1. Get the code**

```sh
git clone https://github.com/MonishKD/phantom.git
cd phantom
```

**2. Make sure the build tools are installed**

```sh
xcode-select --install     # skip this if it says they're already installed
```

**3. Build the app and put it in Applications**

```sh
scripts/install.sh
```

Takes about 30 seconds. Afterwards Phantom opens from Spotlight (⌘-Space, type "Phantom"), from Launchpad, or with `open -a Phantom`. To skip installing and just run it from the repo, use `scripts/build.sh && open dist/Phantom.app`.

**4. Open Phantom and finish the one-time setup**

The first launch shows an **Install** card. Click it. That puts [pymobiledevice3](https://github.com/doronz88/pymobiledevice3), the library that talks to the device, into `~/Library/Application Support/Phantom/venv`. It takes about a minute and uses `uv` if you have it, `python3` otherwise. You can do this ahead of time from a terminal with `scripts/bootstrap.sh`.

**5. Prepare the device**

1. Plug it into the Mac with a cable and unlock it.
2. Tap **Trust** when it asks, and enter the passcode. It then appears in Phantom's sidebar.
3. If the sidebar says Developer Mode is off, click **Show the Developer Mode Switch**. On the device, go to Settings › Privacy & Security › Developer Mode and turn it on. The device restarts, then asks you to confirm.

That's it. Clicking the map now moves the device.

## Everyday use

1. Connect the device, unlock it, and open Phantom.
2. **Click anywhere on the map** to move the device there. You can also search for a place, paste coordinates like `48.8584, 2.2945`, or pick from **Recent**.
3. Turn off **Instant** if you'd rather drop a pin first and press **Teleport Here** yourself.
4. Click **Restore Real Location** when you're done. Quitting Phantom also restores it.

The first teleport after connecting takes a few seconds while Phantom mounts the disk image and opens a tunnel. Each click after that applies immediately.

Leave Phantom open while you need the location: it clears the simulation when you quit, re-sends the location every 15 seconds, and reconnects by itself if the cable or tunnel drops.

## Good to know before you use it

- **Apps can tell.** iOS tags simulated locations with a flag (`isSimulatedBySoftware`) that any app can read, so this cannot be made undetectable. Location games, dating apps, betting apps and banking apps commonly check, and may suspend accounts.
- **Every app sees the fake location at once**, including Find My and anyone you share your location with, Weather, automatic time zone, photo geotags and location-based automations.
- **Emergency calls may report the wrong place.** Restore your real location if you might need them.
- **Nothing here can damage hardware.** It mounts Apple's own signed disk image and uses the same location simulation Xcode uses. The risk is to accounts, not devices.

## Updating

Pushing and pulling move commits; they never rebuild the app. To update the installed copy:

- **After your own changes:** `scripts/install.sh`
- **After pulling someone else's:** `git pull`, then `scripts/install.sh`

To automate the second case, enable the repo's hooks once per clone:

```sh
scripts/setup-hooks.sh      # undo with: git config --unset core.hooksPath
```

This points `core.hooksPath` at `scripts/hooks`. After a pull or branch switch that touches `Sources/`, `helper/`, `Resources/`, `Package.swift` or `scripts/build.sh`, the app is rebuilt and reinstalled — only when Phantom is already installed, so fresh clones stay untouched. A running Phantom is quit first, which lets the helper restore the device's real location on the way out.

Your own commits don't trigger it, on the assumption you build as you work. To change that, add a `post-commit` hook calling `scripts/hooks/lib-auto-install.sh "HEAD~1..HEAD"`.

While working on the helper, `PHANTOM_ROOT=$PWD open -a Phantom` makes the app load `helper/phantom_helper.py` from your checkout, so Python changes need only an app restart instead of a reinstall.

## Uninstalling

```sh
rm -rf /Applications/Phantom.app
rm -rf ~/Library/"Application Support"/Phantom   # the Python environment
git config --unset core.hooksPath                # if you enabled the hooks
```

On the device, turn Developer Mode back off in Settings › Privacy & Security. To drop the pairing with this Mac as well: Settings › General › Transfer or Reset › Reset › Reset Location & Privacy.

## How it works

The app is SwiftUI with MapKit. It runs `helper/phantom_helper.py`, which talks to the device through pymobiledevice3 and exchanges JSON lines with the app over stdin and stdout. The helper reports each device's type, so the app names it ("iPhone", "iPad", …) and picks a matching icon.

- **iOS 17 and later:** the helper mounts the personalized developer disk image and opens an RSD tunnel. It tries Apple's own `remoted` tunnel first, then an in-process userspace tunnel, then a running `tunneld`; the first two need no root. Setting and clearing then both go through CoreDevice's `simulatelocation` feature (`setsimulatedlocation` and `clearsimulatedlocation`). They have to use the same subsystem: a location set through the older DVT instruments service is tracked separately, and CoreDevice's clear reports success without actually releasing it.
- **iOS 16 and earlier:** the helper mounts the classic developer disk image and uses `com.apple.dt.simulatelocation`, which keeps the location after the connection closes.

Either way, apps on the device receive the location through CoreLocation, marked as simulated. `simctl location` is the equivalent for the iOS Simulator; it needs full Xcode and can't reach physical devices, so Phantom doesn't use it.

## Troubleshooting

- **Nothing happens, or you see an error:** open **Activity** in the toolbar for the helper's log.
- **The device never appears:** unlock it, reconnect the cable, and click **Refresh**. Tap Trust if the prompt appears.
- **"Couldn't open a tunnel":** reconnect the cable and unlock the device. As a last resort, run a privileged tunnel in a terminal and try again:
  `sudo ~/Library/Application\ Support/Phantom/venv/bin/python -m pymobiledevice3 remote tunneld`
- **"Couldn't mount the developer disk image":** check your internet connection, since Apple signs the image for each device.
- **The location is still spoofed after a crash:** reopen Phantom and click **Restore Real Location**, or restart the device.

## Layout

```
Sources/Phantom/         SwiftUI app (map, sidebar, helper bridge, installer)
helper/phantom_helper.py device helper (pymobiledevice3)
scripts/build.sh         builds and ad-hoc signs dist/Phantom.app
scripts/install.sh       builds, then installs into /Applications
scripts/bootstrap.sh     installs the Python environment
scripts/setup-hooks.sh   enables the auto-reinstall hooks
scripts/hooks/           post-merge / post-checkout hooks
scripts/make-icon.swift  draws the ghost mark
Resources/Info.plist     app bundle metadata
Resources/AppIcon.icns   app icon
docs/phantom-mark.png    the mark, for this README
```

The icon is vector artwork drawn in code, so it stays crisp at every size. After editing `scripts/make-icon.swift`, regenerate it with:

```sh
swift scripts/make-icon.swift && iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
```
