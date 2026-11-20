import os
import subprocess
import time

EMU_PATH = r"C:\Users\Admin\AppData\Local\Android\Sdk\emulator\emulator.exe"
AVD_NAME = "tb_pixel_api35"

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
        print("Emulator already ready.")
        return None
    print("Starting emulator...")
    p = subprocess.Popen([EMU_PATH, "-avd", AVD_NAME, "-no-window", "-no-audio", "-gpu", "swiftshader_indirect"])
    for i in range(60):
        time.sleep(2)
        if is_ready():
            print(f"Emulator ready after {i*2}s!")
            return p
    print("Timeout waiting for emulator!")
    return p

def main():
    emu = start_emu()
    time.sleep(3)
    
    # Force stop & launch
    print("Stopping and restarting app...")
    adb(["shell", "am", "force-stop", "com.example.thingsboard_democloud_app"])
    time.sleep(1)
    adb(["shell", "am", "start", "-n", "com.example.thingsboard_democloud_app/.MainActivity"])
    
    # Wait 8s for splash screen to disappear and Login Page to fully display
    print("Waiting 8s for Login Page to load...")
    time.sleep(8)
    
    # Capture 01_login_page.png
    print("Capturing 01_login_page.png...")
    adb(["shell", "screencap", "-p", "/sdcard/screen_01.png"])
    subprocess.run(["adb", "-s", "emulator-5554", "pull", "/sdcard/screen_01.png", "docs/screenshots/01_login_page.png"], capture_output=True)
    
    # Try tapping "Try Demo Mode"
    # Button is located below Log In button: center is around (540, 1740)
    print("Tapping Try Demo Mode at (540, 1740)...")
    adb(["shell", "input", "tap", "540", "1740"])
    
    # Wait 5s for transition to Home Page
    print("Waiting 5s for Home Page...")
    time.sleep(5)
    
    # Capture 02_home_page.png
    print("Capturing 02_home_page.png...")
    adb(["shell", "screencap", "-p", "/sdcard/screen_02.png"])
    subprocess.run(["adb", "-s", "emulator-5554", "pull", "/sdcard/screen_02.png", "docs/screenshots/02_home_page.png"], capture_output=True)
    
    print("Test finished.")

if __name__ == "__main__":
    main()
