from PIL import Image
import numpy as np

img = Image.open("docs/screenshots/08_profile_settings.png").convert("RGB")
arr = np.array(img)

# Search for the blue circular icon or chevron around y=950..1200
for y in range(950, 1150, 10):
    # Check chevron on right at x=980
    r, g, b = arr[y, 980]
    print(f"y={y}: at x=980 RGB=({r},{g},{b})")
