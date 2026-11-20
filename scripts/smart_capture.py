import os
import subprocess
import time
import xml.etree.ElementTree as ET
import re

EMU_PATH = r"C:\Users\Admin\AppData\Local\Android\Sdk\emulator\emulator.exe"
AVD_NAME = "tb_pixel_api35"
OUTPUT_DIR = os.path.join("docs", "screenshots")
os.makedirs(OUTPUT_DIR, exist_ok=True)

def adb(args):
    return subprocess.run(["adb", "-s", "emulator-5554"] + args, capture_output=True, text=True)

def is_ready():
    res = subprocess.run(["adb", "devices"], capture_output=True, text=True)
    if "emulator-5554\tdevice" in res.stdout:
        boot = adb(["shell", "getprop", "sys.boot_completed"]).stdout.strip()
        return boot == "1"
    return False

def start_emu():
    if is_ready():
        print("Emulator ready.")
        return None
    print("Starting emulator...")
    p = subprocess.Popen([EMU_PATH, "-avd", AVD_NAME, "-no-window", "-no-audio", "-gpu", "swiftshader_indirect"])
    for _ in range(60):
        time.sleep(2)
        if is_ready():
            print("Ready!")
            return p
    return p

def dump_ui():
    adb(["shell", "uiautomator", "dump", "/sdcard/ui.xml"])
    subprocess.run(["adb", "-s", "emulator-5554", "pull", "/sdcard/ui.xml", "ui_dump.xml"], capture_output=True)
    if os.path.exists("ui_dump.xml"):
        tree = ET.parse("ui_dump.xml")
        return tree.getroot()
    return None

def find_bounds(root, text_pattern):
    if root is None:
        return None
    for node in root.iter("node"):
        txt = node.attrib.get("text", "")
        desc = node.attrib.get("content-desc", "")
        if re.search(text_pattern, txt, re.IGNORECASE) or re.search(text_pattern, desc, re.IGNORECASE):
            bounds = node.attrib.get("bounds", "")
            m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds)
            if m:
                x1, y1, x2, y2 = map(int, m.groups())
                return ((x1 + x2) // 2, (y1 + y2) // 2)
    return None

def tap(x, y):
    print(f"Tapping ({x}, {y})...")
    adb(["shell", "input", "tap", str(x), str(y)])

def capture(name):
    dest = os.path.join(OUTPUT_DIR, name)
    adb(["shell", "screencap", "-p", "/sdcard/temp_screen.png"])
    subprocess.run(["adb", "-s", "emulator-5554", "pull", "/sdcard/temp_screen.png", dest], capture_output=True)
    if os.path.exists(dest):
        sz = os.path.getsize(dest)
        with open(dest, "rb") as f:
            valid = f.read(8) == b"\x89PNG\r\n\x1a\n"
        print(f"Captured {name}: {sz} bytes | Valid: {valid}")

def main():
    emu = start_emu()
    time.sleep(2)
    
    # Force stop & launch
    adb(["shell", "am", "force-stop", "com.example.thingsboard_democloud_app"])
    time.sleep(1)
    adb(["shell", "am", "start", "-n", "com.example.thingsboard_democloud_app/.MainActivity"])
    time.sleep(5)
    
    # 1. Login Page
    capture("01_login_page.png")
    root = dump_ui()
    
    # Look for "Try Demo Mode" or "Demo"
    coords = find_bounds(root, "demo") or (540, 1920)
    tap(*coords)
    time.sleep(4)
    
    # 2. Home Page
    capture("02_home_page.png")
    root = dump_ui()
    
    # 3. Alarms tab
    coords = find_bounds(root, "Alarms") or (405, 2240)
    tap(*coords)
    time.sleep(3)
    capture("03_alarms_page.png")
    
    # 4. Open first alarm
    tap(540, 500)
    time.sleep(3)
    capture("04_alarm_details_page.png")
    adb(["shell", "input", "keyevent", "4"])
    time.sleep(2)
    
    # 5. Devices tab
    root = dump_ui()
    coords = find_bounds(root, "Devices") or (675, 2240)
    tap(*coords)
    time.sleep(3)
    capture("05_devices_page.png")
    
    # 6. Open first device
    tap(540, 500)
    time.sleep(3)
    capture("06_device_details_page.png")
    adb(["shell", "input", "keyevent", "4"])
    time.sleep(2)
    
    # 7. More tab
    root = dump_ui()
    coords = find_bounds(root, "More") or (945, 2240)
    tap(*coords)
    time.sleep(3)
    capture("07_more_page.png")
    
    # 8. Profile & Settings
    root = dump_ui()
    coords = find_bounds(root, "Profile") or (540, 1713)
    tap(*coords)
    time.sleep(3)
    capture("08_profile_settings.png")
    
    # 9. Network & Data Inspector
    root = dump_ui()
    coords = find_bounds(root, "Inspector") or (540, 980)
    tap(*coords)
    time.sleep(3)
    capture("11_network_inspector.png")
    adb(["shell", "input", "keyevent", "4"])
    time.sleep(2)
    
    # 10. Toggle Dark Theme
    root = dump_ui()
    coords = find_bounds(root, "Dark") or (900, 800)
    tap(*coords)
    time.sleep(3)
    capture("09_dark_theme_profile.png")
    
    # 11. More in Dark Theme
    adb(["shell", "input", "keyevent", "4"])
    time.sleep(2)
    capture("10_dark_theme_more.png")
    
    print("All captures completed.")
    adb(["emu", "kill"])

if __name__ == "__main__":
    main()
