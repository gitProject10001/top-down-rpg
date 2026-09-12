"""Compare native gameplay captures; compensate the known one-pixel camera steps."""
from pathlib import Path
import json
import numpy as np
from PIL import Image

folder = Path(__file__).resolve().parents[1] / "captures/shadow_quality"
report = {}
for variant in ("before", "sharp", "temporal"):
    reference = np.asarray(Image.open(folder / f"motion_{variant}_00.png").convert("RGB"), dtype=float)
    errors = []
    # Fixed roof-only patch, excluding foliage, characters and the screen-space label.
    for frame in range(1, 12):
        current = np.asarray(Image.open(folder / f"motion_{variant}_{frame:02}.png").convert("RGB"), dtype=float)
        errors.append(float(np.abs(reference[260:350, 525:635] - current[260:350, 525-frame:635-frame]).mean()))
    report[variant] = {"mean_aligned_rgb_error_0_255": round(float(np.mean(errors)), 3)}

for hour in (-1, 1):
    result = Image.new("RGB", (720, 360))
    for i, variant in enumerate(("before", "sharp")):
        shot = Image.open(folder / f"{variant}_{hour}.png").convert("RGB")
        result.paste(shot.crop((396, 160, 756, 520)), (i * 360, 0))
    result.save(folder / f"comparison_{hour}.png")
(folder / "motion_metrics.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps(report, indent=2))
