#!/usr/bin/env python3
"""Turns the slowed-down frames recorded by `TenFoot --render-snapshots` into a real-speed GIF.

Usage: make-gif.py <frames-dir> <output.gif>
The frames dir holds frame-NNNN.png plus frames.tsv (first line: slowdown factor,
then one "filename<TAB>seconds since start" line per frame).
"""
import sys
from pathlib import Path

from PIL import Image

WIDTH = 960
CROP_TOP, CROP_BOTTOM = 0.22, 0.78  # keep the band around the tile row


def main() -> None:
    frames_dir, out = Path(sys.argv[1]), Path(sys.argv[2])
    lines = (frames_dir / "frames.tsv").read_text().strip().splitlines()
    slowdown = float(lines[0].split("\t")[1])
    entries = [(name, float(t)) for name, t in (line.split("\t") for line in lines[1:])]
    entries = [(n, t) for n, t in entries if (frames_dir / n).exists()]
    if not entries:
        sys.exit("no frames captured")

    images, durations = [], []
    for i, (name, t) in enumerate(entries):
        img = Image.open(frames_dir / name).convert("RGB")
        w, h = img.size
        img = img.crop((0, int(h * CROP_TOP), w, int(h * CROP_BOTTOM)))
        img = img.resize((WIDTH, round(img.height * WIDTH / w)), Image.LANCZOS)
        images.append(img.quantize(colors=255, method=Image.Quantize.MEDIANCUT))
        next_t = entries[i + 1][1] if i + 1 < len(entries) else t + 1.0 * slowdown
        durations.append(max(20, round((next_t - t) / slowdown * 1000)))

    images[0].save(out, save_all=True, append_images=images[1:], duration=durations, loop=0, optimize=True)
    print(f"{out}: {len(images)} frames, {sum(durations) / 1000:.2f}s")


if __name__ == "__main__":
    main()
