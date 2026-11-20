from PIL import Image
import numpy as np

img = Image.open("docs/screenshots/09_dark_theme_profile.png").convert("RGB")
arr = np.array(img)

# In 09_dark_theme_profile.png, let's find the selected button background (light blue)
# System is selected: it has light blue background (around r: 200..235, g: 215..245, b: 245..255)
# Check x = 200 (System segment)
print("Scanning x=200 for selected segment:")
selected_ys = []
for y in range(800, 1600):
    r, g, b = arr[y, 200]
    if 190 <= r <= 235 and 210 <= g <= 245 and b >= 235:
        selected_ys.append(y)

if selected_ys:
    min_y = min(selected_ys)
    max_y = max(selected_ys)
    center_y = (min_y + max_y) // 2
    height = max_y - min_y
    print(f"SegmentedButton selected Y range: {min_y} -> {max_y}, height={height}, center Y = {center_y}")
else:
    print("Could not find selected segment background, dumping RGB at x=200:")
    for y in range(1100, 1400, 20):
        print(f"y={y}: RGB={arr[y, 200]}")
