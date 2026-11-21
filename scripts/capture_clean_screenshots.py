#!/usr/bin/env python3
"""Capture the README screenshot gallery on the Android emulator.

Taps are found by their accessibility label/text through `uiautomator dump`, not by
screen coordinates, so the script survives layout changes (floating nav, other densities).

Usage (from anywhere):
  python -I scripts/capture_clean_screenshots.py [--avd tb_pixel_api35] [--keep-emulator]

Prerequisites: Android SDK (ANDROID_SDK_ROOT, ANDROID_HOME or %LOCALAPPDATA%\\Android\\Sdk),
an AVD, and a debug APK from `flutter build apk --debug`.
"""

import argparse
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_DIR = os.path.join(ROOT, "docs", "screenshots")
APK_PATH = os.path.join(ROOT, "build", "app", "outputs", "flutter-apk", "app-debug.apk")
PACKAGE = "com.example.thingsboard_democloud_app"
SERIAL = "emulator-5554"
BOUNDS = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")


def sdk_dir():
    candidates = [
        os.environ.get("ANDROID_SDK_ROOT"),
        os.environ.get("ANDROID_HOME"),
        os.path.join(os.environ.get("LOCALAPPDATA", ""), "Android", "Sdk"),
    ]
    for path in candidates:
        if path and os.path.isdir(path):
            return path
    sys.exit("Android SDK not found: set ANDROID_SDK_ROOT")


SDK = sdk_dir()
ADB = os.path.join(SDK, "platform-tools", "adb.exe" if os.name == "nt" else "adb")
EMULATOR = os.path.join(SDK, "emulator", "emulator.exe" if os.name == "nt" else "emulator")


def adb(*args, check=False):
    return subprocess.run([ADB, "-s", SERIAL, *args], capture_output=True, text=True, check=check)


def is_ready():
    devices = subprocess.run([ADB, "devices"], capture_output=True, text=True).stdout
    return f"{SERIAL}\tdevice" in devices and adb("shell", "getprop", "sys.boot_completed").stdout.strip() == "1"


def start_emulator(avd):
    if is_ready():
        print("Emulator already running.")
        return None
    print(f"Starting emulator {avd} (headless)...")
    process = subprocess.Popen(
        [EMULATOR, "-avd", avd, "-no-window", "-no-audio", "-no-snapshot-save", "-gpu", "swiftshader_indirect"]
    )
    for _ in range(120):
        time.sleep(3)
        if is_ready():
            print("Emulator ready.")
            return process
    sys.exit("Emulator boot timeout")


def nodes():
    """Clickable nodes of the current screen as (label, (cx, cy))."""
    for _ in range(3):
        adb("shell", "uiautomator", "dump", "/sdcard/ui.xml")
        dump = adb("exec-out", "cat", "/sdcard/ui.xml").stdout
        if "<hierarchy" in dump:
            break
        time.sleep(1)
    else:
        return []
    found = []
    for node in ET.fromstring(dump[dump.index("<hierarchy"):]).iter("node"):
        if node.get("clickable") != "true":
            continue
        label = f"{node.get('content-desc', '')} {node.get('text', '')}".strip()
        match = BOUNDS.match(node.get("bounds", ""))
        if label and match:
            x1, y1, x2, y2 = map(int, match.groups())
            found.append((" ".join(label.split()), ((x1 + x2) // 2, (y1 + y2) // 2)))
    return found


def tap(pattern, timeout=15):
    """Tap the first clickable node whose label matches the regex `pattern`."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        for label, (x, y) in nodes():
            if re.search(pattern, label):
                print(f"  tap {label[:50]!r} at {x},{y}")
                adb("shell", "input", "tap", str(x), str(y))
                time.sleep(2.5)
                return
        time.sleep(1)
    sys.exit(f"Element not found on screen: /{pattern}/")


def wait_for(pattern, timeout=45):
    """Block until a clickable node matching `pattern` is on screen."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if any(re.search(pattern, label) for label, _ in nodes()):
            time.sleep(1)  # let entry animations finish
            return
        time.sleep(1)
    sys.exit(f"Screen never showed: /{pattern}/")


def back():
    adb("shell", "input", "keyevent", "4")
    time.sleep(1.5)


def capture(filename, ready=None):
    """Screenshot the current screen once `ready` (a label regex) is on screen."""
    if ready:
        wait_for(ready)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    destination = os.path.join(OUTPUT_DIR, filename)
    adb("shell", "screencap", "-p", "/sdcard/shot.png")
    subprocess.run([ADB, "-s", SERIAL, "pull", "/sdcard/shot.png", destination], capture_output=True)
    with open(destination, "rb") as handle:
        valid = handle.read(8) == b"\x89PNG\r\n\x1a\n"
    print(f"Captured {filename}: {os.path.getsize(destination)} bytes | valid PNG: {valid}")
    if not valid:
        sys.exit(f"{filename} is not a valid PNG")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--avd", default="tb_pixel_api35")
    parser.add_argument("--keep-emulator", action="store_true")
    args = parser.parse_args()

    emulator = start_emulator(args.avd)
    if not os.path.exists(APK_PATH):
        sys.exit(f"APK not found: {APK_PATH} (run `flutter build apk --debug`)")
    print("Installing APK and resetting app data...")
    adb("install", "-r", APK_PATH, check=True)
    adb("shell", "pm", "clear", PACKAGE)
    adb("shell", "am", "start", "-n", f"{PACKAGE}/.MainActivity")
    wait_for(r"Try Demo Mode")

    capture("01_login_page.png")
    tap(r"Try Demo Mode")
    capture("02_home_page.png", ready=r"^Alarms, ")

    tap(r"^Alarms, ")
    capture("03_alarms_page.png", ready=r"^Critical alarm")
    tap(r"^Critical alarm")
    capture("04_alarm_details_page.png", ready=r"^Acknowledge")
    back()

    tap(r"^Devices")
    capture("05_devices_page.png", ready=r"^All devices")
    tap(r"^All devices")
    tap(r"^Thermostat Thermostat-Floor-1")
    capture("06_device_details_page.png", ready=r"^Telemetry")
    back()
    back()

    tap(r"^More")
    capture("07_more_page.png", ready=r"^Profile & Settings")
    tap(r"^Profile & Settings")
    capture("08_profile_settings.png", ready=r"^Network & Data Inspector")
    tap(r"^Network & Data Inspector")
    capture("11_network_inspector.png", ready=r"^ALL$")
    back()

    tap(r"^Dark$")
    time.sleep(1.5)  # let the theme cross-fade finish
    capture("09_dark_theme_profile.png", ready=r"^Network & Data Inspector")
    back()
    capture("10_dark_theme_more.png", ready=r"^Profile & Settings")

    if not args.keep_emulator and emulator is not None:
        print("Stopping emulator...")
        adb("emu", "kill")
    print("Done.")


if __name__ == "__main__":
    main()
