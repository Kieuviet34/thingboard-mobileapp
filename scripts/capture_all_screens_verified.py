import os
import subprocess
import time
from PIL import Image
import numpy as np

EMU_PATH = r"C:\Users\Admin\AppData\Local\Android\Sdk\emulator\emulator.exe"
AVD_NAME = "tb_pixel_api35"
OUTPUT_DIR = os.path.join("docs", "screenshots")
os.makedirs(OUTPUT_DIR, exist_ok=True)

def run_cmd(cmd_list):
    try:
        res = subprocess.run(cmd_list, capture_output=True, text=True, timeout=30)
        return res.stdout.strip()
    except Exception as e:
        print(f"Error running {cmd_list}: {e}")
        return ""

def adb(args):
    return run_cmd(["adb", "-s", "emulator-5554"] + args)

def is_ready():
    res = run_cmd(["adb", "devices"])
    if "emulator-5554\tdevice" in res:
        boot = adb(["shell", "getprop", "sys.boot_completed"])
        return boot == "1"
    return False

def start_emu():
    if is_ready():
        print("Emulator already running and ready.")
        return None
    print("Starting Android emulator...")
    p = subprocess.Popen([
        EMU_PATH,
        "-avd", AVD_NAME,
        "-no-window",
        "-no-audio",
        "-gpu", "swiftshader_indirect",
        "-memory", "2048"
    ])
    print("Waiting 15s for emulator process initialization...")
    time.sleep(15)
    for i in range(25):
        time.sleep(3)
        if is_ready():
            print(f"Emulator ready after {15 + (i+1)*3}s!")
            return p
    print("Warning: timeout waiting for boot_completed.")
    return p

def tap(x, y, desc=""):
    print(f"  -> Tap ({x}, {y}) {desc}")
    adb(["shell", "input", "tap", str(x), str(y)])

def key_back():
    print("  -> Press Back key")
    adb(["shell", "input", "keyevent", "4"])

def get_current_screen_array(save_path=None):
    temp_remote = "/sdcard/temp_screen.png"
    temp_local = save_path or "temp_check.png"
    adb(["shell", "screencap", "-p", temp_remote])
    subprocess.run(["adb", "-s", "emulator-5554", "pull", temp_remote, temp_local], capture_output=True)
    if os.path.exists(temp_local):
        img = Image.open(temp_local).convert("RGB")
        return np.array(img)
    return None

def capture(filename):
    dest = os.path.join(OUTPUT_DIR, filename)
    get_current_screen_array(save_path=dest)
    if os.path.exists(dest):
        sz = os.path.getsize(dest)
        with open(dest, "rb") as f:
            valid = f.read(8) == b"\x89PNG\r\n\x1a\n"
        print(f"  [SAVED] {filename} ({sz:,} bytes, PNG valid: {valid})")
    else:
        print(f"  [FAILED] {filename} not saved!")

def wait_for_login_page():
    print("Waiting for Login Page to replace Splash Screen...")
    for sec in range(25):
        arr = get_current_screen_array()
        if arr is not None and arr.shape[0] >= 1900 and arr.shape[1] >= 550:
            r, g, b = arr[1871, 540]
            # Try Demo Mode button is light blue (r in 180..240, g in 200..250, b >= 225)
            if 180 <= r <= 240 and 200 <= g <= 250 and b >= 225:
                print(f"  Login Page detected at t={sec}s! (Button pixel RGB: {r},{g},{b})")
                return True
        time.sleep(1)
    print("  Fallback: proceeding to capture.")
    return False

def main():
    emu_p = start_emu()
    time.sleep(2)

    print("\n--- 1. App Launch & Login Screen ---")
    adb(["shell", "am", "force-stop", "com.example.thingsboard_democloud_app"])
    time.sleep(1)
    adb(["shell", "am", "start", "-n", "com.example.thingsboard_democloud_app/.MainActivity"])
    
    wait_for_login_page()
    time.sleep(2)
    capture("01_login_page.png")

    print("\n--- 2. Enter Demo Mode & Home Page ---")
    # Tap "Try Demo Mode" button at verified center (540, 1871)
    tap(540, 1871, desc="Try Demo Mode button")
    print("Waiting 8s for Demo Mode load & navigation to Home...")
    time.sleep(8)
    capture("02_home_page.png")

    print("\n--- 3. Alarms Page ---")
    # Tap Tab 1: Alarms (x=405, y=2280)
    tap(405, 2280, desc="Alarms Tab")
    time.sleep(4)
    capture("03_alarms_page.png")

    print("\n--- 4. Alarm Details Page ---")
    # Tap first alarm card (x=540, y=550)
    tap(540, 550, desc="First Alarm Card")
    time.sleep(4)
    capture("04_alarm_details_page.png")
    key_back()
    time.sleep(2)

    print("\n--- 5. Devices Page ---")
    # Tap Tab 2: Devices (x=675, y=2280)
    tap(675, 2280, desc="Devices Tab")
    time.sleep(4)
    capture("05_devices_page.png")

    print("\n--- 6. Device Details Page ---")
    # Tap "All devices" card (x=540, y=450) to open device list
    tap(540, 450, desc="All Devices Profile Card")
    time.sleep(3)
    # Tap first device (x=540, y=550) to open Device Details & Telemetry
    tap(540, 550, desc="First Device -> Details & Telemetry")
    time.sleep(4)
    capture("06_device_details_page.png")
    key_back()
    time.sleep(2)
    key_back()
    time.sleep(2)

    print("\n--- 7. More Page ---")
    # Tap Tab 3: More (x=945, y=2280)
    tap(945, 2280, desc="More Tab")
    time.sleep(4)
    capture("07_more_page.png")

    print("\n--- 8. Profile & Settings Page ---")
    # Tap user header card on More page (x=540, y=360)
    tap(540, 360, desc="User Header Card -> Profile")
    time.sleep(4)
    capture("08_profile_settings.png")

    print("\n--- 9. Network & Data Inspector Sheet ---")
    # Tap Network & Data Inspector tile at verified (540, 2100)
    tap(540, 2100, desc="Network & Data Inspector Tile")
    time.sleep(4)
    capture("11_network_inspector.png")
    key_back()
    time.sleep(2)

    print("\n--- 10. Dark Theme - Profile Settings ---")
    # Tap 'Dark' in SegmentedButton at verified (747, 1425)
    tap(747, 1425, desc="Theme Dark Segment")
    time.sleep(4)
    capture("09_dark_theme_profile.png")

    print("\n--- 11. Dark Theme - More Page ---")
    key_back()
    time.sleep(3)
    capture("10_dark_theme_more.png")

    print("\nAll 11 screenshots successfully captured!")
    print("Shutting down emulator...")
    adb(["emu", "kill"])

if __name__ == "__main__":
    main()
