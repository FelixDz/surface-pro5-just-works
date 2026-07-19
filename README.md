# surface-pro5-just-works

Kamera-Fix und Verwaltungs-Suite für das **Microsoft Surface Pro 5 (Model 1796)** unter Linux – ohne den ganzen Microsoft-Mist, einfach und gut.

> ⚠️ **Keine lange Testphase** – direkt aus der Entwicklung. Funktioniert auf Kernel 6.19 mit linux-surface.

## Das Problem

Das Surface Pro 5 hat drei Kameras (Frontkamera OV5693, Rückkamera OV8865, IR-Kamera OV7251) die unter Kernel 6.19 komplett kaputt sind. Zwei separate Kernel-Bugs verhindern dass libcamera die Kameras überhaupt findet.

## Die Lösung

Drei Fixes + ein selbstlernender On-Demand Daemon + GTK Switcher.

### Fix 1: dw9719 VCM Treiber (Kernel 6.19 Regression)
Der Autofokus-Motor der Rückkamera hat in Kernel 6.19 keine `i2c_device_id` Tabelle mehr. Er blockiert dadurch den async Notifier und verhindert dass libcamera die Kameras findet.

**Symptom:** `cam --list` zeigt keine Kameras.

### Fix 2: int3472 avdd Quirk (Surface Pro 5 spezifisch)
Der INT3472 ACPI-Treiber mappt GPIO 150/151 als "privacy-led" statt als `avdd` Spannungsversorgung. Die Kameras bekommen keine Spannung.

**Symptom:** `dmesg | grep avdd` zeigt `avdd not found`.

### Fix 3: v4l2loopback für Kernel 6.19
Die DKMS-Version 0.12.7 ist inkompatibel (geänderte `v4l2_fh_add/del` API). Wird aus dem aktuellen GitHub-Source gebaut.

### Daemon + Switcher
- **Selbstlernend**: Erkennt automatisch welche Apps die Kamera nutzen
- **On-Demand**: Kamera-LED nur an wenn wirklich genutzt
- **GTK Switcher**: Kleines Fenster zum Wechseln zwischen Front- und Rückkamera

## Dateien

| Datei | Beschreibung |
|-------|-------------|
| `surface-kamera-daemon.c` | On-Demand Daemon |
| `surface-kamera-switcher.py` | GTK Switcher-Fenster |
| `install.sh` | Automatischer Installer |

## Installation

```bash
git clone https://github.com/EberhartLeberhart/surface-pro5-just-works.git
cd surface-pro5-just-works
chmod +x install.sh
./install.sh
```

**Nicht als root ausführen!** Der Installer nutzt sudo intern.

## Nach der Installation

```bash
# Kameras prüfen
cam --list
# Sollte zeigen:
# 1: Internal back camera
# 2: Internal front camera

# Daemon Status
systemctl --user status surface-kamera-daemon
```

## Verwendung

Der Daemon startet automatisch beim Login. Wenn OBS, Firefox, Zoom, Teams oder eine andere bekannte App startet:

1. Frontkamera Pipeline startet sofort auf `/dev/video20` ("Surface Kamera")
2. Nach 2 Sekunden erscheint das **Switcher-Fenster**
3. `[📷 Front]` / `[📸 Rück]` zum Wechseln
4. `[🔄 Neu]` bei grünem Bild der Rückkamera

### Neue Apps hinzufügen

Der Daemon lernt automatisch – einfach die App starten und die Kamera öffnen. Oder manuell:

```bash
echo "meine-app" | sudo tee -a /etc/surface-kamera/known-apps.conf
```

## Getestete Konfiguration

- **Gerät**: Microsoft Surface Pro 5 (Model 1796)
- **CPU**: Intel Core m3-7Y30
- **Kernel**: 6.19.8-surface-3 ([linux-surface](https://github.com/linux-surface/linux-surface))
- **libcamera**: 0.6.0
- **Getestet mit**: OBS, Firefox, Cheese

## Bekannte Einschränkungen

- **Grünes Bild** bei der Rückkamera: Fehlende ISP Tuning-Kalibrierung für den OV8865. `[🔄 Neu]` hilft.
- **IR-Kamera**: Nicht unterstützt.
- **Kernel 6.18**: Funktioniert auch, aber ohne Daemon-Integration nötig.

## Lizenz

GPL v2
