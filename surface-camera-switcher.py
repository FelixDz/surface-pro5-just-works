#!/usr/bin/env python3
"""
Surface camera Switcher
This one is started by the daemon when a known app uses the camera.
Communicates with the daemon via /tmp/surface-camera-cmd
"""
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib, Gdk
import os
import subprocess
import sys

CMD_FILE = "/tmp/surface-camera-cmd"
POLL_MS  = 1000

class CameraSwitcher(Gtk.Window):
    def __init__(self, active="front"):
        super().__init__(title="🎥 Surface Camera")
        self.active = active
        self.set_default_size(280, 120)
        self.set_resizable(False)
        self.set_keep_above(True)
        self.set_border_width(12)
        self.connect("destroy", self.on_stop)

        css = b"""
        window { background-color: #1a1a2e; }
        label { color: #e0e0e0; font-size: 13px; }
        .btn-active { background: #4ecca3; color: #1a1a2e; border: none;
                     border-radius: 8px; padding: 10px; font-weight: bold;
                     font-size: 13px; }
        .btn-inactive { background: #0f3460; color: #888; border: none;
                       border-radius: 8px; padding: 10px; font-size: 13px; }
        """
        p = Gtk.CssProvider()
        p.load_from_data(css)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), p,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(vbox)

        self.status = Gtk.Label(label="Camera is active")
        self.status.set_halign(Gtk.Align.CENTER)
        vbox.pack_start(self.status, False, False, 0)

        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        vbox.pack_start(hbox, False, False, 0)

        self.btn_front = Gtk.Button(label="📷 Front camera")
        self.btn_front.connect("clicked", self.on_front)
        hbox.pack_start(self.btn_front, True, True, 0)

        self.btn_rear = Gtk.Button(label="📸 Rear camera")
        self.btn_rear.connect("clicked", self.on_rear)
        hbox.pack_start(self.btn_rear, True, True, 0)

        self.update_buttons()

        # Check if the daemon still runs
        GLib.timeout_add_seconds(2, self.check_daemon)

    def update_buttons(self):
        for btn, name in [(self.btn_front, "front"), (self.btn_rear, "rear")]:
            ctx = btn.get_style_context()
            ctx.remove_class("btn-active")
            ctx.remove_class("btn-inactive")
            ctx.add_class("btn-active" if self.active == name else "btn-inactive")
        camera = "Front camera" if self.active == "front" else "Rear camera"
        self.status.set_text(f"Active: {camera}")

    def send_cmd(self, cmd):
        try:
            with open(CMD_FILE, 'w') as f:
                f.write(cmd)
        except:
            pass

    def on_front(self, w):
        if self.active != "front":
            self.active = "front"
            self.send_cmd("front")
            self.update_buttons()

    def on_rear(self, w):
        if self.active != "rear":
            self.active = "rear"
            self.send_cmd("rear")
            self.update_buttons()

    def check_daemon(self):
        # Close the window if the dameon no longer runs
        result = subprocess.run(
            ["pgrep", "-x", "surface-camera"],
            capture_output=True)
        if result.returncode != 0:
            Gtk.main_quit()
            return False
        return True

    def on_stop(self, w):
        Gtk.main_quit()

# Choose the start camera from argument
active = sys.argv[1] if len(sys.argv) > 1 else "front"
app = CameraSwitcher(active)
app.show_all()
Gtk.main()
