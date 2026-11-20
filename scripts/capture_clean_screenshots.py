import os
import subprocess
import time
import sys

EMU_PATH = r"C:\Users\Admin\AppData\Local\Android\Sdk\emulator\emulator.exe"
AVD_NAME = "tb_pixel_api35"
OUTPUT_DIR = os.path.join("docs", "screenshots")

os.makedirs(OUTPUT_DIR, exist_ok=True)

def adb(args):
    return subprocess.run(["adb", "-s", "emulator-5554"] + args, capture_output=True, text=True)

def is_device_ready():
    res = subprocess.run(["adb", "devices"], capture_output=True, text=True)
    if "emulator-5554\tdevice" in res.stdout:
        boot = adb(["shell", "getprop", "sys.boot_completed"]).stdout.strip()
        return boot == "1"
    return False

def start_emulator():
    if is_device_ready():
        print("Emulator already running and ready.")
        return None
    print("Starting emulator in headless mode...")
    p = subprocess.Popen([EMU_PATH, "-avd", AVD_NAME, "-no-window", "-no-audio", "-gpu", "swiftshader_indirect"])
    print("Waiting for device boot...")
    for _ in range(60):
        time.sleep(2)
        if is_device_ready():
            print("Device is ready!")
            return p
    print("Emulator boot timeout!")
    return p

def capture(filename):
    dest = os.path.join(OUTPUT_DIR, filename)
    adb(["shell", "screencap", "-p", "/sdcard/temp_screen.png"])
    subprocess.run(["adb", "-s", "emulator-5554", "pull", "/sdcard/temp_screen.png", dest], capture_output=True)
    if os.path.exists(dest):
        with open(dest, "rb") as f:
            header = f.read(8)
            is_valid = header == b"\x89PNG\r\n\x1a\n"
            size = os.path.getsize(dest)
            print(f"Captured {filename}: {size} bytes | Valid PNG: {is_valid}")
            if not is_valid:
                print(f"ERROR: {filename} has header {header}")
    else:
        print(f"FAILED to pull {filename}")

APK_PATH = os.path.join("build", "app", "outputs", "flutter-apk", "app-debug.apk")

def main():
    emu_proc = start_emulator()
    time.sleep(2)
    
    if os.path.exists(APK_PATH):
        print(f"Installing updated APK from {APK_PATH}...")
        install_res = subprocess.run(["adb", "-s", "emulator-5554", "install", "-r", APK_PATH], capture_output=True, text=True)
        print("Install result:", install_res.stdout.strip() or install_res.stderr.strip())
    else:
        print(f"APK not found at {APK_PATH}, using installed version.")

    # Launch app
    print("Launching app...")
    adb(["shell", "am", "start", "-n", "com.example.thingsboard_democloud_app/.MainActivity"])
    time.sleep(5)
    
    # 1. Login Page
    capture("01_login_page.png")
    
    # 2. Tap Try Demo Mode (x=540, y=1903)
    print("Navigating to Home via Demo mode...")
    adb(["shell", "input", "tap", "540", "1903"])
    time.sleep(4)
    capture("02_home_page.png")
    
    # 3. Tab 2: Alarms (x=405, y=2232)
    print("Navigating to Alarms...")
    adb(["shell", "input", "tap", "405", "2232"])
    time.sleep(2)
    capture("03_alarms_page.png")
    
    # 4. First alarm details (x=540, y=600)
    print("Opening Alarm Details...")
    adb(["shell", "input", "tap", "540", "600"])
    time.sleep(2)
    capture("04_alarm_details_page.png")
    adb(["shell", "input", "keyevent", "4"])
    time.sleep(1)
    
    # 5. Tab 3: Devices (x=675, y=2232)
    print("Navigating to Devices...")
    adb(["shell", "input", "tap", "675", "2232"])
    time.sleep(2)
    capture("05_devices_page.png")
    
    # 6. First device details (x=540, y=600)
    print("Opening Device Details...")
    adb(["shell", "input", "tap", "540", "600"])
    time.sleep(2)
    capture("06_device_details_page.png")
    adb(["shell", "input", "keyevent", "4"])
    time.sleep(1)
    
    # 7. Tab 4: More (x=945, y=2232)
    print("Navigating to More...")
    adb(["shell", "input", "tap", "945", "2232"])
    time.sleep(2)
    capture("07_more_page.png")
    
    # 8. Profile & Settings (x=540, y=1713)
    print("Opening Profile & Settings...")
    adb(["shell", "input", "tap", "540", "1713"])
    time.sleep(2)
    capture("08_profile_settings.png")
    
    # 8b. Network & Data Inspector (x=540, y=980)
    print("Opening Network Inspector...")
    adb(["shell", "input", "tap", "540", "980"])
    time.sleep(2)
    capture("11_network_inspector.png")
    adb(["shell", "input", "keyevent", "4"])
    time.sleep(1)
    
    # 9. Toggle Dark Theme (x=900, y=800)
    print("Toggling Dark theme...")
    adb(["shell", "input", "tap", "900", "800"])
    time.sleep(2)
    capture("09_dark_theme_profile.png")
    
    # 10. More in Dark Theme
    adb(["shell", "input", "keyevent", "4"])
    time.sleep(2)
    capture("10_dark_theme_more.png")
    
    # Stop emulator
    print("Stopping emulator...")
    adb(["emu", "kill"])
    print("Finished screenshot capture successfully.")

if __name__ == "__main__":
    main()
