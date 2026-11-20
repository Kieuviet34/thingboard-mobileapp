from PIL import Image
import numpy as np

img = Image.open("docs/screenshots/08_profile_settings.png").convert("RGB")
arr = np.array(img)
h, w, _ = arr.shape
print(f"Dimensions: {w}x{h}")

# Find Theme Mode segment at x=700 (Dark button icon or text)
print("Scanning SegmentedButton near x=700:")
for y in range(1100, 1350, 10):
    r, g, b = arr[y, 700]
    # Check if border or text
    if not (r > 240 and g > 240 and b > 240):
        print(f"  Dark Segment y={y}: RGB=({r},{g},{b})")

# Find Network & Data Inspector tile near x=540
print("\nScanning Network & Data Inspector near x=540:")
for y in range(1650, 1900, 10):
    r, g, b = arr[y, 105] # Circular icon on left
    print(f"  Inspector icon y={y}: RGB=({r},{g},{b})")
