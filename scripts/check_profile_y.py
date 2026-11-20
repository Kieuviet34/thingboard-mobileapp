from PIL import Image
import numpy as np

img = Image.open("docs/screenshots/08_profile_settings.png").convert("RGB")
arr = np.array(img)

# Search for the "Theme Mode" segmented button
# In 08_profile_settings.png, find the row with the SegmentedButton border
for y in range(400, 800, 10):
    # Check pixels across x=200, 500, 700
    r, g, b = arr[y, 700]
    # Let's inspect
    print(f"y={y}: at x=700 RGB=({r},{g},{b})")
