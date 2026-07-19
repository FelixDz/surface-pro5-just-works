# surface-pro5-just-works

Camera-fix und control-suite for the **Microsoft Surface Pro 5 (Model 1796)** under Linux – without the full Microsoft-trash, easy und working.

> ⚠️ **No long testphase** – straight from the development phase. Works with the `linux-surface` 6.19 kernel.

## The Problem

The Surface Pro 5 has three cameras (Front camera OV5693, Rear camera OV8865, IR camera OV7251) that are completely broken under the 6.19 kernel. Two separate kernel bugs prevent licamera from finding the cameras at all in the first place.

## The Solution

Three fixes + a self-learning on-demand daemon + a GTK switcher.

### Fix 1: dw9719 VCM driver (Kernel 6.19 regression)
The autofocus-motor of the Rear camera lacks the `i2c_device_id` table in the 6.19 kernel. This blocks the async notifier and prevents libcamera from finding the cameras.

**Symptom:** `cam --list` shows no camera.

### Fix 2: int3472 avdd quirk (Surface Pro 5 specific)
The INT3472 ACPI-driver maps GPIO 150/151 as "privacy-led" instead of `avdd` power-management. The cameras are not powered.

**Symptom:** `dmesg | grep avdd` shows `avdd not found`.

### Fix 3: v4l2loopback for kernel 6.19
The DKMS 0.12.7 version is not compatible (change in the `v4l2_fh_add/del` API). Thus it is built from the current GitHub source instead.

### Daemon + switcher
- **Self-learning**: automagically learns which apps use the camera
- **On-demand**: the camera LED is only lit when the camera is actually used
- **GTK switcher**: a small window to help switching between the front and rear cameras

## Code

| File | Description |
|-------|-------------|
| `surface-camera-daemon.c` | On-demand daemon |
| `surface-camera-switcher.py` | GTK switcher window |
| `install.sh` | Automatic installer |

## Installation

```bash
git clone https://github.com/EberhartLeberhart/surface-pro5-just-works.git
cd surface-pro5-just-works
chmod +x install.sh
./install.sh
```

**Do not run as root !** The installer uses sudo internally.

## Post-install

```bash
# Check the cameras
cam --list
# Should show:
# 1: Internal back camera
# 2: Internal front camera

# Daemon status
systemctl --user status surface-camera-daemon
```

## Usage

The dameon automatically starts with login. When OBS, Firefox, Zoom, Teams or another known app runs:

1. The front camera pipeline starts immediately on `/dev/video20` ("Surface Camera")
2. After 2 seconds, the **switcher window** appear
3. Click `[📷 Front]` / `[📸 Rear]` to select the wanted camera
4. Click `[🔄 Refresh]` if you get a green image from the rear camera

### Add new "known apps"

The daemonautomatically learns – simply start the app and run the camera. Or manually:

```bash
echo "the-app-you-want-to-add" | sudo tee -a /etc/surface-camera/known-apps.conf
```

## Tested configuration

- **Device**: Microsoft Surface Pro 5 (Model 1796)
- **CPU**: Intel Core m3-7Y30
- **Kernel**: 6.19.8-surface-3 ([linux-surface](https://github.com/linux-surface/linux-surface))
- **libcamera**: 0.6.0
- **Tested with**: OBS, Firefox, Cheese

## Known bugs

- **Green image** when using the rear camera: missing ISP tuning calibration for the OV8865. `[🔄 Refresh]` helps.
- **IR camera**: not supported.
- **Kernel 6.18**: also works, without needing the daemon integration.

## License

GPL v2
