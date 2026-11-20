from PIL import Image
import numpy as np

img = Image.open("docs/screenshots/02_home_page.png").convert("RGB")
arr = np.array(img)
h, w, _ = arr.shape
print(f"Image shape: width={w}, height={h}")

# The "Log In" button is dark blue (r ~ 40, g ~ 80, b ~ 125)
# The "Try Demo Mode" button is light blue (r ~ 210, g ~ 225, b ~ 250)

login_ys = []
demo_ys = []

for y in range(1500, 2100):
    r, g, b = arr[y, 540]
    if r < 60 and g < 100 and b > 100: # Dark blue Log In button
        login_ys.append(y)
    elif r > 190 and r < 235 and g > 210 and b > 230: # Light blue Demo button
        demo_ys.append(y)

if login_ys:
    print(f"Log In button Y range: {min(login_ys)} -> {max(login_ys)}, center Y = {(min(login_ys) + max(login_ys)) // 2}")
if demo_ys:
    print(f"Try Demo Mode button Y range: {min(demo_ys)} -> {max(demo_ys)}, center Y = {(min(demo_ys) + max(demo_ys)) // 2}")
