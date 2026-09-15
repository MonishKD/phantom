# phantom
spoof your location and movements.

Phantom is a macOS app that sets your iPhone's or iPad's GPS location to wherever you click on a map. It works over a USB cable, and it doesn't need root or a jailbreak.

## Requirements

- macOS 14 or later, with the Xcode Command Line Tools (`xcode-select --install`). Full Xcode isn't needed.
- An iPhone or iPad connected by cable with **Developer Mode** turned on (iOS/iPadOS 16+). Wi-Fi-only iPads work too, since the location is injected in software.
- Internet access the first time you connect: the developer disk image is downloaded and signed by Apple.

## Build and run

```sh
scripts/build.sh          # builds dist/Phantom.app
open dist/Phantom.app
```

On first launch the app offers a one-time **Install** step. It puts [pymobiledevice3](https://github.com/doronz88/pymobiledevice3) into `~/Library/Application Support/Phantom/venv`, using `uv` if you have it and `python3` otherwise. You can also run `scripts/bootstrap.sh` yourself.

## Using it

1. Plug in the iPhone or iPad, unlock it, and tap **Trust**. The device appears in the sidebar.
2. If the sidebar says Developer Mode is off, click **Show the Developer Mode Switch**. Then on the device go to Settings › Privacy & Security › Developer Mode, turn it on, and confirm after it restarts.
3. **Click anywhere on the map** to move the device there. You can also search for a place, paste coordinates like `48.8584, 2.2945`, or pick from **Recent**.
4. Turn off **Instant** if you'd rather drop a pin first and press **Teleport Here** yourself.
5. Click **Restore Real Location** when you're done. Quitting Phantom also restores it.

The first teleport per connection takes a few seconds while Phantom mounts the disk image and opens a tunnel. After that, each click applies right away.

## How it works

The app is SwiftUI with MapKit. It runs `helper/phantom_helper.py`, which talks to the device through pymobiledevice3 and exchanges JSON lines with the app over stdin and stdout. The helper reports each device's type, so the app names it ("iPhone", "iPad", …) and picks a matching icon.

- **iOS 17 and later:** the helper mounts the personalized developer disk image and opens an RSD tunnel. It tries Apple's own `remoted` tunnel first, then an in-process userspace tunnel, then a running `tunneld`; the first two need no root. It then drives the Instruments `LocationSimulation` service. The simulated location only lasts while that connection is open, so the helper keeps it open, re-sends the location every 15 seconds, and reconnects if the cable or tunnel drops.
- **iOS 16 and earlier:** the helper mounts the classic developer disk image and uses `com.apple.dt.simulatelocation`.

## Troubleshooting

- **Nothing happens or you see an error:** open **Activity** in the toolbar to see the helper's log.
- **"Couldn't open a tunnel":** reconnect the cable and unlock the phone. As a last resort, run a privileged tunnel in Terminal and try again:
  `sudo ~/Library/Application\ Support/Phantom/venv/bin/python -m pymobiledevice3 remote tunneld`
- **"Couldn't mount the developer disk image":** check your internet connection, since Apple signs the image for each device.
- **The location is still spoofed after a crash:** restart the device, or launch Phantom and click **Restore Real Location**.

## Layout

```
Sources/Phantom/        SwiftUI app (map, sidebar, helper bridge, installer)
helper/phantom_helper.py device helper (pymobiledevice3)
scripts/build.sh        builds and ad-hoc signs dist/Phantom.app
scripts/bootstrap.sh    installs the Python environment
Resources/Info.plist    app bundle metadata
```
