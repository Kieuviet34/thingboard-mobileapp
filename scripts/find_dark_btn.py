from PIL import Image
import numpy as np

img = Image.open("docs/screenshots/09_dark_theme_profile.png").convert("RGB")
arr = np.array(img)

# In 09_dark_theme_profile.png, let's find the dark icon or text "Dark" inside SegmentedButton
# At y=1200..1500, scan x from 600 to 800
# The moon icon "dark_mode_outlined" and text "Dark" have color onSurface (r ~ 40..60, g ~ 40..60, b ~ 40..60)
dark_pixels = []
for y in range(1200, 1500):
    for x in range(600, 850):
        r, g, b = arr[y, x]
        if r < 70 and g < 70 and b < 70:
            dark_pixels.append((x, y))

if dark_pixels:
    xs = [p[0] for p in dark_pixels]
    ys = [p[1] for p in dark_pixels]
    print(f"Dark button contents: X range {min(xs)}..{max(xs)} (center {(min(xs)+max(xs))//2}), Y range {min(ys)}..{max(ys)} (center {(min(ys)+max(ys))//2})")
else:
    print("Not found in 1200..1500, scanning wider:")
    for y in range(1000, 1600, 50):
        print(f"y={y}: min RGB in [600..850] = {min([arr[y,x][0] for x in range(600, 850)])}")
