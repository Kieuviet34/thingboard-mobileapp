from PIL import Image
import numpy as np

img = Image.open("docs/screenshots/09_dark_theme_profile.png").convert("RGB")
arr = np.array(img)

# Search for the SegmentedButton around x=830 (Dark segment)
print("Finding SegmentedButton Y range at x=830:")
dark_ys = []
for y in range(500, 1600):
    r, g, b = arr[y, 830]
    # Check if inside button (not white background 248, 249, 255)
    # The text "Dark" is dark grey (r < 100, g < 100, b < 100)
    if r < 100 and g < 100 and b < 100:
        dark_ys.append(y)

if dark_ys:
    print(f"Dark text Y range: {min(dark_ys)} -> {max(dark_ys)}, center = {(min(dark_ys)+max(dark_ys))//2}")
else:
    print("Could not find dark text automatically, scanning color transitions:")
    for y in range(1200, 1500, 20):
        print(f"y={y}: at x=830 RGB={arr[y, 830]}")

# Also find Network Inspector tile in 08_profile_settings.png:
# In 08_profile_settings.png, Network Inspector tile has an icon at left (x ~ 105)
img8 = Image.open("docs/screenshots/08_profile_settings.png").convert("RGB")
arr8 = np.array(img8)
for y in range(1900, 2200, 20):
    print(f"y={y}: at x=105 RGB={arr8[y, 105]}, at x=540 RGB={arr8[y, 540]}")
