#!/usr/bin/env python3
"""Render headless, transparent-background animation loops of both cats (issue #27).

The desktop pet is drawn by two SwiftUI renderers - `KiwiPetView.drawPet` for the
procedural Kiwi and `SpriteCharacterRenderer.draw` for the layered Kot-Arbuz
sprite. This script is a straight port of both to Pillow so the same motion can
be rendered anywhere, with no display and no window server, onto a transparent
canvas.

Everything is drawn at `SS` times the output size and downsampled with LANCZOS,
which is what stands in for the anti-aliasing SwiftUI gets for free.

Shot list, one 15 s loop per cat:

| # | Shot        | Mood                 | Seconds | What it shows                              |
| - | ----------- | -------------------- | ------- | ------------------------------------------ |
| 1 | idle        | `idle`               | 3.0     | breathing, blink, eyes tracking the cursor |
| 2 | walk        | `walking`            | 2.4     | tripod leg cycle / paw step                |
| 3 | dance       | `dancing`            | 2.4     | sway + hop + paw bounce, celebration burst |
| 4 | hearts      | `celebrating`        | 2.4     | petting hearts                             |
| 5 | waiting     | `waitingForApproval` | 2.4     | amber halo, `?` glyph, raised paw          |
| 6 | celebration | `celebrating`        | 2.4     | celebration effect + agent badge and pips  |

Output is a 420 x 420 loop at 12.5 fps (80 ms per frame, the cadence of the
existing `*-demo.gif` assets), 188 frames, 15 s, in both animated WebP (full
alpha, the good one) and GIF (1-bit alpha, for renderers that need it).

Shots 4 and 6 are the same `celebrating` mood; 6 adds the agent badge with three
session pips so the loop also covers the agent-awareness drawing.

Requires Pillow and NumPy (development helper only; the app never runs it).

Usage:
    python3 Scripts/render-character-animations.py            # render both cats
    python3 Scripts/render-character-animations.py --cat kiwi
    python3 Scripts/render-character-animations.py --check    # verify outputs
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image, ImageDraw
except ImportError as error:  # pragma: no cover - development helper only
    print(f"render-character-animations.py needs Pillow and NumPy: {error}", file=sys.stderr)
    raise SystemExit(2)

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "Resources" / "Art" / "Rendered"
SKIN_ROOT = ROOT / "Resources" / "PetSkins"

# --- output geometry --------------------------------------------------------
OUTPUT = 420           # square output canvas, in pixels (matches the existing demo GIFs)
SS = 3                 # supersample factor; the render canvas is OUTPUT * SS
FPS = 12.5             # 80 ms per frame, the same cadence as the existing demo GIFs
LOOP_SECONDS = 15.0
FRAMES = int(round(LOOP_SECONDS * FPS))

# --- shared colours from AgentIndicator.swift -------------------------------
WORKING_COLOR = (0x7E, 0xD1, 0x8A)
WAITING_COLOR = (0xE5, 0xA9, 0x3C)
PALE_FILL = (0xF5, 0xEF, 0xCF)
PUPIL_COLOR = (0x30, 0x28, 0x2C)

IDLE = "idle"
WORKING = "working"
CELEBRATING = "celebrating"
DANCING = "dancing"
STRETCHING = "stretching"
CURIOUS = "curious"
BREAK_REMINDER = "breakReminder"
RESTING = "resting"
DRAGGING = "dragging"
WALKING = "walking"
WAITING_FOR_APPROVAL = "waitingForApproval"

OFF = "off"
LIGHT_WORKING = "working"
LIGHT_WAITING = "waiting"


# ===========================================================================
# small math helpers
# ===========================================================================

def clamp(value: float, low: float, high: float) -> float:
    return low if value < low else (high if value > high else value)


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def radians(degrees: float) -> float:
    return degrees * math.pi / 180.0


def rotate_point(point, pivot, cos_sin) -> tuple[float, float]:
    c, s = cos_sin
    dx, dy = point[0] - pivot[0], point[1] - pivot[1]
    return (pivot[0] + c * dx - s * dy, pivot[1] + s * dx + c * dy)


def flatten_quad(p0, p1, p2, steps: int = 0):
    if steps <= 0:
        length = math.dist(p0, p1) + math.dist(p1, p2)
        steps = int(clamp(length / 3.0, 8, 64))
    out = []
    for index in range(1, steps + 1):
        t = index / steps
        u = 1.0 - t
        out.append(
            (
                u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
                u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1],
            )
        )
    return out


def flatten_cubic(p0, p1, p2, p3, steps: int = 0):
    if steps <= 0:
        length = math.dist(p0, p1) + math.dist(p1, p2) + math.dist(p2, p3)
        steps = int(clamp(length / 3.0, 8, 64))
    out = []
    for index in range(1, steps + 1):
        t = index / steps
        u = 1.0 - t
        a, b, c, d = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t
        out.append(
            (
                a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
                a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1],
            )
        )
    return out


class BezierPath:
    """The subset of SwiftUI `Path` the two renderers use."""

    def __init__(self) -> None:
        self.subpaths: list[list[tuple[float, float]]] = []

    def move_to(self, point) -> None:
        self.subpaths.append([tuple(point)])

    def add_line(self, point) -> None:
        if not self.subpaths:
            self.subpaths.append([])
        self.subpaths[-1].append(tuple(point))

    def add_quad_curve(self, to, control) -> None:
        if not self.subpaths:
            self.subpaths.append([])
        self.subpaths[-1].extend(flatten_quad(self.subpaths[-1][-1], control, to))

    def add_curve(self, to, control1, control2) -> None:
        if not self.subpaths:
            self.subpaths.append([])
        self.subpaths[-1].extend(flatten_cubic(self.subpaths[-1][-1], control1, control2, to))

    def bounds(self):
        xs = [p[0] for sub in self.subpaths for p in sub]
        ys = [p[1] for sub in self.subpaths for p in sub]
        return (min(xs), min(ys), max(xs), max(ys))


# ===========================================================================
# canvas
# ===========================================================================

class Canvas:
    """An RGBA drawing surface that composites shapes through masks.

    Every composite is clipped to the shape's bounding box; a 1440 px canvas
    times ~40 shapes times 300 frames would otherwise spend most of its time
    blending fully transparent pixels.
    """

    def __init__(self, size: tuple[int, int]) -> None:
        self.size = size
        self.image = Image.new("RGBA", size, (0, 0, 0, 0))

    # -- clipping ----------------------------------------------------------
    def _clip(self, box, pad: int = 2):
        x0, y0, x1, y1 = box
        bx0 = max(0, int(math.floor(min(x0, x1))) - pad)
        by0 = max(0, int(math.floor(min(y0, y1))) - pad)
        bx1 = min(self.size[0], int(math.ceil(max(x0, x1))) + pad)
        by1 = min(self.size[1], int(math.ceil(max(y0, y1))) + pad)
        if bx1 <= bx0 or by1 <= by0:
            return None
        return (bx0, by0, bx1, by1)

    def _path_mask(self, path: BezierPath, offset: tuple[int, int], size: tuple[int, int]) -> Image.Image:
        mask = Image.new("L", size, 0)
        draw = ImageDraw.Draw(mask)
        for sub in path.subpaths:
            if len(sub) >= 3:
                draw.polygon([(p[0] - offset[0], p[1] - offset[1]) for p in sub], fill=255)
        return mask

    def _composite(self, draw_fn, box, rgb, alpha: float, pad: int = 2):
        """`rgb` is a colour tuple or an (h, w, 3) array; `alpha` is 0...1."""
        if alpha <= 0.001:
            return
        clipped = self._clip(box, pad=pad)
        if clipped is None:
            return
        bx0, by0, bx1, by1 = clipped
        mask = Image.new("L", (bx1 - bx0, by1 - by0), 0)
        draw_fn(ImageDraw.Draw(mask), (bx0, by0))
        self.composite_mask(mask, (bx0, by0), rgb, alpha)

    def composite_mask(self, mask: Image.Image, origin, rgb, alpha: float) -> None:
        """Blend `rgb` through `mask` (an L image) at `origin`."""
        mask_array = np.asarray(mask, dtype=np.uint16)
        if mask_array.max() == 0:
            return
        height, width = mask_array.shape
        layer = np.zeros((height, width, 4), dtype=np.uint8)
        layer[:, :, :3] = rgb
        layer[:, :, 3] = (mask_array * min(alpha, 1.0)).astype(np.uint8)
        self.image.alpha_composite(Image.fromarray(layer, "RGBA"), (origin[0], origin[1]))

    # -- shapes ------------------------------------------------------------
    def fill_path(self, path: BezierPath, color, opacity: float = 1.0) -> None:
        def draw(mask: ImageDraw.ImageDraw, offset) -> None:
            for sub in path.subpaths:
                if len(sub) >= 3:
                    mask.polygon([(p[0] - offset[0], p[1] - offset[1]) for p in sub], fill=255)

        self._composite(draw, path.bounds(), color, opacity)

    def fill_gradient_path(self, path: BezierPath, start_color, end_color, start, end, opacity: float = 1.0) -> None:
        bounds = path.bounds()
        clipped = self._clip(bounds)
        if clipped is None:
            return
        bx0, by0, bx1, by1 = clipped
        mask = self._path_mask(path, (bx0, by0), (bx1 - bx0, by1 - by0))
        gradient = linear_gradient((bx1 - bx0, by1 - by0), start_color, end_color, start, end, (bx0, by0))
        self.composite_mask(mask, (bx0, by0), gradient, opacity)

    def stroke_path(self, path: BezierPath, color, width: float, opacity: float = 1.0) -> None:
        line_width = max(int(round(width)), 1)

        def draw(mask: ImageDraw.ImageDraw, offset) -> None:
            for sub in path.subpaths:
                if len(sub) < 2:
                    continue
                points = [(p[0] - offset[0], p[1] - offset[1]) for p in sub]
                mask.line(points, fill=255, width=line_width, joint="curve")

        # Half the width sits outside the path, so the clip has to grow with it
        # or the outer edge of a thick stroke gets cut off.
        self._composite(draw, path.bounds(), color, opacity, pad=int(math.ceil(line_width / 2.0)) + 2)

    def ellipse(self, box, fill=None, fill_opacity: float = 1.0, outline=None, width: float = 0,
                outline_opacity: float = 1.0) -> None:
        """`box` is (x, y, width, height) like CGRect, not two corners."""
        x, y, w, h = box
        corners = (x, y, x + w, y + h)
        if fill is not None:
            self._composite(
                lambda m, o: m.ellipse((corners[0] - o[0], corners[1] - o[1], corners[2] - o[0], corners[3] - o[1]), fill=255),
                corners,
                fill,
                fill_opacity,
            )
        if outline is not None and width > 0:
            line_width = max(int(round(width)), 1)
            self._composite(
                lambda m, o: m.ellipse(
                    (corners[0] - o[0], corners[1] - o[1], corners[2] - o[0], corners[3] - o[1]),
                    outline=255,
                    width=line_width,
                ),
                corners,
                outline,
                outline_opacity,
            )

    def rounded_rect(self, box, radius: float, color, opacity: float = 1.0) -> None:
        x, y, w, h = box
        corners = (x, y, x + w, y + h)
        self._composite(
            lambda m, o: m.rounded_rectangle(
                (corners[0] - o[0], corners[1] - o[1], corners[2] - o[0], corners[3] - o[1]),
                radius=max(radius, 0),
                fill=255,
            ),
            corners,
            color,
            opacity,
        )

    def line(self, points, color, width: float, opacity: float = 1.0) -> None:
        line_width = max(int(round(width)), 1)
        xs = [p[0] for p in points]
        ys = [p[1] for p in points]
        self._composite(
            lambda m, o: m.line([(p[0] - o[0], p[1] - o[1]) for p in points], fill=255, width=line_width, joint="curve"),
            (min(xs), min(ys), max(xs), max(ys)),
            color,
            opacity,
        )

    # -- bitmaps -----------------------------------------------------------
    def draw_affine(self, source: Image.Image, rect, coeffs, box) -> None:
        """Paste `source` with a dest -> source affine, clipped to `box`.

        `coeffs` is (A, B, C, D, E, F) mapping a canvas pixel (X, Y) to a source
        pixel (u, v). `rect` is the placement box, only used to derive the clip
        box when the caller does not pass one.
        """
        a, b, c, d, e, f = coeffs
        x0, y0, x1, y1 = box
        bx0 = max(0, int(math.floor(x0)))
        by0 = max(0, int(math.floor(y0)))
        bx1 = min(self.size[0], int(math.ceil(x1)))
        by1 = min(self.size[1], int(math.ceil(y1)))
        if bx1 <= bx0 or by1 <= by0:
            return
        layer = source.transform(
            (bx1 - bx0, by1 - by0),
            Image.AFFINE,
            (a, b, a * bx0 + b * by0 + c, d, e, d * bx0 + e * by0 + f),
            resample=Image.BICUBIC,
            fillcolor=(0, 0, 0, 0),
        )
        self.image.alpha_composite(layer, (bx0, by0))

    def paste(self, layer: Image.Image, origin) -> None:
        self.image.alpha_composite(layer, (int(round(origin[0])), int(round(origin[1]))))

    def transform_whole(self, forward, inverse_affine) -> Image.Image:
        """Apply `inverse_affine` (dest -> source) to the whole canvas."""
        a, b, c, d, e, f = inverse_affine
        return self.image.transform(
            self.size, Image.AFFINE, (a, b, c, d, e, f), resample=Image.BICUBIC, fillcolor=(0, 0, 0, 0)
        )


def linear_gradient(size, start_color, end_color, start, end, origin) -> np.ndarray:
    """A `LinearGradient` from `start` to `end`, sampled over `size` pixels.

    SwiftUI clamps the gradient before `start` and after `end`, and projects
    each pixel onto the start/end segment.
    """
    width, height = size
    xs = np.arange(width, dtype=np.float32) + origin[0]
    ys = np.arange(height, dtype=np.float32) + origin[1]
    grid_x, grid_y = np.meshgrid(xs, ys)
    dx, dy = end[0] - start[0], end[1] - start[1]
    length_squared = dx * dx + dy * dy
    if length_squared <= 0:
        t = np.zeros((height, width), dtype=np.float32)
    else:
        t = ((grid_x - start[0]) * dx + (grid_y - start[1]) * dy) / length_squared
        t = np.clip(t, 0.0, 1.0)
    t = t[:, :, None]
    start_array = np.array(start_color, dtype=np.float32)
    end_array = np.array(end_color, dtype=np.float32)
    return (start_array * (1.0 - t) + end_array * t).astype(np.uint8)


# ===========================================================================
# PetShapes.swift
# ===========================================================================

def star(center, outer_radius: float, inner_radius: float) -> BezierPath:
    path = BezierPath()
    points = []
    for index in range(8):
        angle = index * math.pi / 4 - math.pi / 2
        radius = outer_radius if index % 2 == 0 else inner_radius
        points.append((center[0] + math.cos(angle) * radius, center[1] + math.sin(angle) * radius))
    path.subpaths.append(points)
    return path


def heart(center, size: float) -> BezierPath:
    path = BezierPath()
    cx, cy = center
    path.move_to((cx, cy + size * 0.78))
    path.add_curve((cx - size, cy - size * 0.08), (cx - size * 1.15, cy + size * 0.40), (cx - size, cy + size * 0.33))
    path.add_curve((cx, cy - size * 0.18), (cx - size * 0.90, cy - size * 0.70), (cx - size * 0.25, cy - size * 0.82))
    path.add_curve((cx + size, cy - size * 0.08), (cx + size * 0.25, cy - size * 0.82), (cx + size * 0.90, cy - size * 0.70))
    path.add_curve((cx, cy + size * 0.78), (cx + size, cy + size * 0.33), (cx + size * 1.15, cy + size * 0.40))
    return path


def crescent(center, radius: float) -> BezierPath:
    path = BezierPath()
    cx, cy = center
    path.move_to((cx, cy - radius))
    path.add_quad_curve((cx, cy + radius), (cx + radius * 1.35, cy))
    path.add_quad_curve((cx, cy - radius), (cx - radius * 0.30, cy + radius * 0.15))
    return path


def leaf(canvas: Canvas, start, end, radius: float, color, opacity: float = 1.0) -> None:
    midpoint = ((start[0] + end[0]) / 2.0, (start[1] + end[1]) / 2.0)
    path = BezierPath()
    path.move_to(start)
    path.add_quad_curve(end, (midpoint[0] - radius * 0.42, midpoint[1]))
    path.add_quad_curve(start, (midpoint[0] + radius * 0.42, midpoint[1] + radius * 0.25))
    canvas.fill_path(path, color, opacity)
    canvas.line([start, end], (255, 255, 255), max(radius * 0.10, 0.6), 0.38)


def plus_spark(canvas: Canvas, center, arm: float, thickness: float, color, opacity: float = 1.0) -> None:
    canvas.rounded_rect((center[0] - arm, center[1] - thickness / 2, arm * 2, thickness), thickness / 2, color, opacity)
    canvas.rounded_rect((center[0] - thickness / 2, center[1] - arm, thickness, arm * 2), thickness / 2, color, opacity)


def celebration_alpha(time: float, reduced_motion: bool = False) -> float:
    if reduced_motion:
        return 0.8
    window = 2.0
    progress = (time % window) / window
    if progress < 0:
        progress += 1.0
    return 0.9 * smoothstep(0, 0.2, progress) * (1.0 - smoothstep(0.6, 1.0, progress))


def celebration_base(canvas: Canvas, center, radius: float, time: float, palette, fade: float) -> None:
    halo_pulse = 1.0 + 0.06 * math.sin(time * 5.0)
    halo_base = 0.10 + 0.12 * (0.5 + 0.5 * math.sin(time * 5.0))
    half_w = radius * 1.16 * halo_pulse
    half_h = radius * 0.98 * halo_pulse
    canvas.ellipse(
        (center[0] - half_w, center[1] - half_h, half_w * 2, half_h * 2),
        outline=palette["accent"],
        width=max(radius * 0.05, 1),
        outline_opacity=min(halo_base * fade, 1.0),
    )
    for x, y, phase in ((-1.12, -0.78, 0.0), (1.12, -0.82, 2.1), (-1.06, 0.44, 4.2), (1.04, 0.48, 1.05)):
        point = (center[0] + x * radius, center[1] + y * radius)
        blink = max(0.0, math.sin(time * 3.0 + phase)) ** 2.0
        if blink <= 0.02:
            continue
        arm = radius * 0.09 * (0.85 + 0.15 * blink)
        plus_spark(canvas, point, arm, max(arm * 0.38, 0.8), palette["furLight"], min(blink * fade, 1.0))


# ===========================================================================
# AgentIndicator.swift
# ===========================================================================

def draw_badge(canvas: Canvas, center, radius: float, palette, light: str, count: int,
               animated: bool, time: float) -> None:
    """Chest badge light plus the session-count pips (the sprite path)."""
    if light == OFF:
        return
    badge_radius = max(radius * 0.20, 3.0)
    is_waiting = light == LIGHT_WAITING
    tint = WAITING_COLOR if is_waiting else WORKING_COLOR

    ring_box = (center[0] - badge_radius, center[1] - badge_radius, badge_radius * 2, badge_radius * 2)
    canvas.ellipse(ring_box, fill=PALE_FILL, fill_opacity=0.94)
    canvas.ellipse(ring_box, outline=palette["outline"], width=max(radius * 0.026, 1.0), outline_opacity=0.82)

    if is_waiting:
        outer = badge_radius * 1.34
        canvas.ellipse(
            (center[0] - outer, center[1] - outer, outer * 2, outer * 2),
            outline=WAITING_COLOR,
            width=max(radius * 0.045, 1.4),
            outline_opacity=0.92,
        )

    pulse = 0.65 + 0.35 * (0.5 + 0.5 * math.sin(time * 2.8)) if animated else 0.85
    core_radius = badge_radius * 0.58
    canvas.ellipse(
        (center[0] - core_radius, center[1] - core_radius, core_radius * 2, core_radius * 2),
        fill=tint,
        fill_opacity=pulse,
    )
    draw_session_count(canvas, center, count, tint, badge_radius, palette)


def draw_session_count(canvas: Canvas, center, count: int, tint, badge_radius: float, palette) -> None:
    if count <= 0:
        return
    max_pips = 5
    shown = min(count, max_pips)
    diameter = max(badge_radius * 0.62, 5.0)
    gap = max(badge_radius * 0.20, 1.8)
    plus_width = gap + diameter * 0.9 if count > max_pips else 0.0
    total_width = diameter * shown + gap * (shown - 1) + plus_width
    center_y = center[1] + badge_radius + gap + diameter / 2
    cursor = center[0] - total_width / 2 + diameter / 2
    for _ in range(shown):
        box = (cursor - diameter / 2, center_y - diameter / 2, diameter, diameter)
        canvas.ellipse(box, fill=tint, fill_opacity=0.95)
        canvas.ellipse(box, outline=palette["outline"], width=max(badge_radius * 0.055, 0.8), outline_opacity=0.88)
        cursor += diameter + gap
    if count <= max_pips:
        return
    stroke_width = max(diameter * 0.28, 1.2)
    arm = diameter * 0.42
    plus_center = (cursor - gap + plus_width / 2, center_y)
    canvas.line([(plus_center[0] - arm, plus_center[1]), (plus_center[0] + arm, plus_center[1])],
                palette["outline"], stroke_width, 0.92)
    canvas.line([(plus_center[0], plus_center[1] - arm), (plus_center[0], plus_center[1] + arm)],
                palette["outline"], stroke_width, 0.92)


def glyph(symbol: str, center, height: float):
    """`?` / `!` geometry: (path, dot_center, dot_radius)."""
    path = BezierPath()
    if symbol == "question":
        path.move_to((center[0] - height * 0.21, center[1] - height * 0.24))
        path.add_quad_curve(
            (center[0] + height * 0.21, center[1] - height * 0.24),
            (center[0], center[1] - height * 0.50),
        )
        path.add_line((center[0] + height * 0.21, center[1] - height * 0.06))
        path.add_line((center[0], center[1] + height * 0.10))
        dot_center = (center[0], center[1] + height * 0.36)
    else:
        path.move_to((center[0], center[1] - height * 0.44))
        path.add_line((center[0], center[1] + height * 0.16))
        dot_center = (center[0], center[1] + height * 0.42)
    return path, dot_center, height * 0.085


def draw_glyph_badge(canvas: Canvas, center, height: float, symbol: str = "question") -> None:
    halo_radius = height * 0.46
    canvas.ellipse(
        (center[0] - halo_radius, center[1] - halo_radius * 0.98, halo_radius * 2, halo_radius * 2),
        fill=WAITING_COLOR,
        fill_opacity=0.22,
    )
    canvas.ellipse(
        (center[0] - halo_radius, center[1] - halo_radius * 0.98, halo_radius * 2, halo_radius * 2),
        outline=WAITING_COLOR,
        width=max(height * 0.062, 1.0),
        outline_opacity=0.85,
    )
    path, dot_center, dot_radius = glyph(symbol, center, height)
    outer_width = max(height * 0.21, 1.6)
    core_width = max(height * 0.12, 1.0)
    canvas.stroke_path(path, (255, 255, 255), outer_width, 0.96)
    canvas.stroke_path(path, WAITING_COLOR, core_width, 1.0)
    outer_dot = dot_radius + (outer_width - core_width) / 2
    canvas.ellipse(
        (dot_center[0] - outer_dot, dot_center[1] - outer_dot, outer_dot * 2, outer_dot * 2),
        fill=(255, 255, 255),
        fill_opacity=0.96,
    )
    canvas.ellipse(
        (dot_center[0] - dot_radius, dot_center[1] - dot_radius, dot_radius * 2, dot_radius * 2),
        fill=WAITING_COLOR,
        fill_opacity=1.0,
    )


# ===========================================================================
# palettes
# ===========================================================================

class PetPalette:
    """`PetPalette` + `PetRenderProfile`, straight from `KiwiPetView.swift`."""

    def __init__(self, colors: dict, animation: dict) -> None:
        self.fur = hex_color(colors["fur"])
        self.fur_light = hex_color(colors["furLight"])
        self.outline = hex_color(colors["outline"])
        self.inner_ear = hex_color(colors["innerEar"])
        self.iris = hex_color(colors["iris"])
        self.accent = hex_color(colors["accent"])
        self.cheek = hex_color(colors["cheek"])
        self.breathing_frequency = float(animation["breathingFrequency"])
        self.breathing_amplitude = float(animation["breathingAmplitude"])
        self.tail_frequency = float(animation["tailFrequency"])
        self.tail_amplitude = float(animation["tailAmplitude"])
        self.celebration_effect = animation.get("celebrationEffect", "leaves")

    def as_dict(self) -> dict:
        return {
            "fur": self.fur,
            "furLight": self.fur_light,
            "outline": self.outline,
            "innerEar": self.inner_ear,
            "iris": self.iris,
            "accent": self.accent,
            "cheek": self.cheek,
        }


def hex_color(value: str):
    value = value.lstrip("#")
    number = int(value, 16)
    return ((number >> 16) & 0xFF, (number >> 8) & 0xFF, number & 0xFF)


def load_palette(skin_id: str) -> PetPalette:
    skin = json.loads((SKIN_ROOT / skin_id / "skin.json").read_text(encoding="utf-8"))
    return PetPalette(skin["colors"], skin["animation"])


# ===========================================================================
# KiwiPetView.swift - the procedural cat
# ===========================================================================

def cat_head_path(center, radius: float) -> BezierPath:
    cx, cy = center
    path = BezierPath()
    path.move_to((cx - radius * 0.76, cy + radius * 0.44))
    path.add_curve(
        (cx - radius * 0.88, cy - radius * 0.33),
        (cx - radius * 1.00, cy + radius * 0.15),
        (cx - radius * 0.98, cy - radius * 0.12),
    )
    path.add_line((cx - radius * 0.84, cy - radius * 1.02))
    path.add_quad_curve((cx - radius * 0.32, cy - radius * 0.69), (cx - radius * 0.52, cy - radius * 0.88))
    path.add_curve(
        (cx + radius * 0.32, cy - radius * 0.69),
        (cx - radius * 0.12, cy - radius * 0.58),
        (cx + radius * 0.12, cy - radius * 0.58),
    )
    path.add_quad_curve((cx + radius * 0.84, cy - radius * 1.02), (cx + radius * 0.52, cy - radius * 0.88))
    path.add_line((cx + radius * 0.88, cy - radius * 0.33))
    path.add_curve(
        (cx + radius * 0.76, cy + radius * 0.44),
        (cx + radius * 0.98, cy - radius * 0.12),
        (cx + radius * 1.00, cy + radius * 0.15),
    )
    path.add_curve(
        (cx - radius * 0.76, cy + radius * 0.44),
        (cx + radius * 0.47, cy + radius * 0.99),
        (cx - radius * 0.47, cy + radius * 0.99),
    )
    return path


def inner_ear_path(center, radius: float, side: float) -> BezierPath:
    cx, cy = center
    sign = side
    path = BezierPath()
    path.move_to((cx + sign * radius * 0.68, cy - radius * 0.64))
    path.add_line((cx + sign * radius * 0.77, cy - radius * 0.88))
    path.add_quad_curve(
        (cx + sign * radius * 0.48, cy - radius * 0.71),
        (cx + sign * radius * 0.59, cy - radius * 0.79),
    )
    return path


def closed_eye_path(center, radius: float, happy: bool) -> BezierPath:
    cx, cy = center
    path = BezierPath()
    path.move_to((cx - radius, cy))
    path.add_quad_curve((cx + radius, cy), (cx, cy + radius * (1.22 if happy else 0.72)))
    return path


def head_tilt_angle(time: float, mood: str, reduced_motion: bool) -> float:
    if reduced_motion or mood not in (IDLE, WORKING):
        return 0.0
    period, duration = 18.0, 2.0
    phase = time % period
    if phase >= duration:
        return 0.0
    t = phase / duration
    envelope = smoothstep(0, 0.4, t) * (1 - smoothstep(0.6, 1.0, t))
    cycle = int(math.floor(time / period))
    direction = 1.0 if cycle % 2 == 0 else -1.0
    return direction * radians(7.0) * envelope


def draw_kiwi(canvas: Canvas, size, time: float, mood: str, palette: PetPalette, gaze,
              light: str, agent_count: int, attention, animated: bool = True) -> None:
    """Port of `KiwiPetView.drawPet` (the non-sprite branch)."""
    width, height = size
    radius = min(width, height) * 0.335
    center = (width * 0.50, height * 0.55)
    head_center = (center[0], center[1] - radius * 0.23)
    profile = palette

    is_dancing = mood == DANCING and animated
    is_stretching = mood == STRETCHING
    is_waiting = mood == WAITING_FOR_APPROVAL
    dance_sway = math.sin(time * 6.2) * radius * 0.055 if is_dancing else 0.0
    dance_bounce = abs(math.sin(time * 6.2)) * radius * 0.075 if is_dancing else 0.0
    stretch_lift = radius * 0.035 if is_stretching else 0.0
    feed_bounce = light == LIGHT_WORKING
    breath_frequency = profile.breathing_frequency * (1.25 if feed_bounce else 1.0)
    breath = math.sin(time * breath_frequency) * profile.breathing_amplitude if animated else 0.0
    work_bob = abs(math.sin(time * 2.4)) * radius * 0.012 if (feed_bounce and animated) else 0.0
    bob = math.sin(time * 1.45) * radius * 0.018 if animated else 0.0

    body_center = (center[0] + dance_sway, center[1] + bob - dance_bounce - work_bob)
    head_bob = (
        head_center[0] + dance_sway * 0.32,
        head_center[1] + bob - dance_bounce * 0.42 - stretch_lift - work_bob,
    )
    posed_breath = breath + (0.045 if is_stretching else 0.0)

    if mood in (WORKING, CELEBRATING, DANCING, BREAK_REMINDER, WAITING_FOR_APPROVAL):
        halo_opacity = (
            0.15 if mood in (CELEBRATING, DANCING) else (0.13 if mood in (BREAK_REMINDER, WAITING_FOR_APPROVAL) else 0.08)
        )
        halo_color = WAITING_COLOR if is_waiting else palette.accent
        canvas.ellipse(
            (center[0] - radius * 1.16, center[1] - radius * 0.98, radius * 2.32, radius * 2.32),
            fill=halo_color,
            fill_opacity=halo_opacity,
        )

    draw_kiwi_tail(canvas, body_center, radius, time, palette, mood, animated)
    draw_kiwi_body(canvas, body_center, radius, palette, posed_breath)

    head_tilt = head_tilt_angle(time, mood, not animated)
    if head_tilt != 0.0:
        group = Canvas((width, height))
        draw_kiwi_head(group, head_bob, radius, palette, posed_breath)
        draw_kiwi_face(group, head_bob, radius, time, palette, mood, gaze, animated)
        draw_kiwi_cheek_heart(group, head_bob, radius, time, palette, mood, animated)
        cos_sin = (math.cos(-head_tilt), math.sin(-head_tilt))
        rotated = rotate_canvas(group.image, head_bob, cos_sin)
        canvas.paste(rotated, (0, 0))
    else:
        draw_kiwi_head(canvas, head_bob, radius, palette, posed_breath)
        draw_kiwi_face(canvas, head_bob, radius, time, palette, mood, gaze, animated)
        draw_kiwi_cheek_heart(canvas, head_bob, radius, time, palette, mood, animated)

    draw_kiwi_paws(canvas, body_center, radius, palette, time, mood, animated)
    draw_kiwi_badge(
        canvas,
        (center[0] + dance_sway * 0.45, center[1] + radius * 0.40 + bob - dance_bounce - work_bob),
        radius,
        palette,
        time,
        mood,
        animated,
        light,
        agent_count,
    )

    if mood in (CELEBRATING, DANCING):
        draw_celebration_effect(canvas, center, radius, time, palette, palette.celebration_effect)
    if mood in (CURIOUS, BREAK_REMINDER, WAITING_FOR_APPROVAL):
        sparkle = (center[0] + radius * 0.83, center[1] - radius * 0.82)
        sparkle_color = WAITING_COLOR if is_waiting else palette.accent
        canvas.fill_path(star(sparkle, radius * 0.11, radius * 0.045), sparkle_color, 0.90)
    if attention is not None:
        draw_glyph_badge(
            canvas,
            (width * 0.5, height * 0.105),
            min(width, height) * 0.16,
            attention,
        )


def draw_kiwi_tail(canvas: Canvas, center, radius: float, time: float, palette: PetPalette,
                   mood: str, animated: bool) -> None:
    if mood == DANCING:
        amplitude = palette.tail_amplitude * 1.8
    elif mood == WORKING:
        amplitude = palette.tail_amplitude
    else:
        amplitude = palette.tail_amplitude * 0.55
    wag = math.sin(time * palette.tail_frequency) * radius * amplitude if animated else 0.0
    if mood in (CELEBRATING, DANCING):
        lifted = -radius * 0.18
    elif mood == STRETCHING:
        lifted = -radius * 0.10
    else:
        lifted = 0.0
    base = (center[0] + radius * 0.52, center[1] + radius * 0.46)
    tip = (center[0] + radius * 1.24, center[1] + radius * 0.22 + wag + lifted)
    path = BezierPath()
    path.move_to(base)
    path.add_curve(
        tip,
        (center[0] + radius * 0.95, center[1] + radius * 0.67 + wag * 0.55),
        (center[0] + radius * 1.26, center[1] + radius * 0.77 + wag + lifted),
    )
    canvas.stroke_path(path, palette.outline, radius * 0.19, 1.0)
    canvas.stroke_path(path, palette.fur, radius * 0.125, 1.0)
    canvas.ellipse((tip[0] - radius * 0.055, tip[1] - radius * 0.055, radius * 0.11, radius * 0.11),
                   fill=palette.fur_light)


def draw_kiwi_body(canvas: Canvas, center, radius: float, palette: PetPalette, breath: float) -> None:
    box = (center[0] - radius * 0.64, center[1] - radius * 0.10, radius * 1.28, radius * (1.10 + breath))
    corners = (box[0], box[1], box[0] + box[2], box[1] + box[3])
    clipped = canvas._clip(corners)
    if clipped is not None:
        bx0, by0, bx1, by1 = clipped
        mask = Image.new("L", (bx1 - bx0, by1 - by0), 0)
        ImageDraw.Draw(mask).ellipse(
            (corners[0] - bx0, corners[1] - by0, corners[2] - bx0, corners[3] - by0), fill=255
        )
        gradient = linear_gradient(
            (bx1 - bx0, by1 - by0),
            palette.fur_light,
            palette.fur,
            (corners[0], corners[1]),
            (corners[2], corners[3]),
            (bx0, by0),
        )
        canvas.composite_mask(mask, (bx0, by0), gradient, 1.0)
    canvas.ellipse(box, outline=palette.outline, width=max(radius * 0.045, 1.5))
    canvas.ellipse(
        (center[0] - radius * 0.39, center[1] + radius * 0.16, radius * 0.78, radius * 0.67),
        fill=palette.fur_light,
        fill_opacity=0.50,
    )


def draw_kiwi_head(canvas: Canvas, center, radius: float, palette: PetPalette, breath: float) -> None:
    head = cat_head_path(center, radius * (1 + breath * 0.3))
    canvas.fill_gradient_path(
        head,
        palette.fur_light,
        palette.fur,
        (center[0] - radius * 0.8, center[1] - radius),
        (center[0] + radius * 0.8, center[1] + radius * 0.8),
    )
    canvas.stroke_path(head, palette.outline, max(radius * 0.045, 1.5), 1.0)
    for side in (-1.0, 1.0):
        canvas.fill_path(inner_ear_path(center, radius, side), palette.inner_ear, 0.83)
    leaf_base = (center[0], center[1] - radius * 0.76)
    leaf(canvas, leaf_base, (center[0] - radius * 0.17, center[1] - radius * 1.00), radius * 0.105, palette.accent)
    leaf(canvas, leaf_base, (center[0] + radius * 0.16, center[1] - radius * 1.02), radius * 0.105, palette.accent, 0.9)
    leaf(canvas, leaf_base, (center[0], center[1] - radius * 1.08), radius * 0.11, palette.accent)


def draw_kiwi_face(canvas: Canvas, center, radius: float, time: float, palette: PetPalette,
                   mood: str, gaze, animated: bool) -> None:
    is_happy = mood in (CELEBRATING, DANCING)
    is_resting = mood in (RESTING, STRETCHING)
    eyes_wide = mood in (CURIOUS, BREAK_REMINDER, WAITING_FOR_APPROVAL)
    is_blinking = animated and (time % 4.6) < 0.14
    eye_y = center[1] + radius * 0.06
    eye_gap = radius * 0.285
    eye_width = radius * 0.105
    eye_height = radius * 0.155

    for side in (-1.0, 1.0):
        canvas.ellipse(
            (center[0] + side * radius * 0.39 - radius * 0.12, center[1] + radius * 0.31, radius * 0.24, radius * 0.12),
            fill=palette.cheek,
            fill_opacity=0.46,
        )

    for side in (-1.0, 1.0):
        eye_center = (center[0] + side * eye_gap, eye_y)
        if is_happy or is_resting or is_blinking:
            arc = closed_eye_path(eye_center, eye_width * 1.04, is_happy)
            canvas.stroke_path(arc, palette.outline, max(radius * 0.055, 1.7), 1.0)
        else:
            scale = 2.15 if eyes_wide else 1.7
            eye_box = (
                eye_center[0] - eye_width,
                eye_center[1] - eye_height * 0.52,
                eye_width * 2,
                eye_height * scale,
            )
            canvas.ellipse(eye_box, fill=palette.outline)
            gaze_x = gaze[0] * radius * 0.052
            gaze_y = gaze[1] * radius * 0.050
            iris = (eye_box[0] + eye_width * 0.22 + gaze_x, eye_box[1] + eye_height * 0.14 + gaze_y,
                    eye_box[2] - eye_width * 0.44, eye_box[3] - eye_height * 0.28)
            canvas.ellipse(iris, fill=palette.iris)
            pupil = (eye_center[0] - eye_width * 0.31 + gaze_x * 1.12,
                     eye_center[1] - eye_height * 0.33 + gaze_y * 1.12,
                     eye_width * 0.62, eye_height * 0.72)
            canvas.ellipse(pupil, fill=PUPIL_COLOR)
            shine = (eye_center[0] - eye_width * 0.22 + gaze_x * 0.78,
                     eye_center[1] - eye_height * 0.38 + gaze_y * 0.78,
                     eye_width * 0.22, eye_width * 0.22)
            canvas.ellipse(shine, fill=(255, 255, 255), fill_opacity=0.94)

    # Nose: a small filled curve, then the mouth.
    nose = BezierPath()
    nose.move_to((center[0], center[1] + radius * 0.24))
    nose.add_quad_curve(
        (center[0] - radius * 0.085, center[1] + radius * 0.17),
        (center[0] - radius * 0.08, center[1] + radius * 0.16),
    )
    nose.add_quad_curve(
        (center[0] + radius * 0.085, center[1] + radius * 0.17),
        (center[0], center[1] + radius * 0.27),
    )
    nose.add_quad_curve(
        (center[0], center[1] + radius * 0.24),
        (center[0] + radius * 0.08, center[1] + radius * 0.16),
    )
    canvas.fill_path(nose, palette.inner_ear)

    if eyes_wide:
        mouth = (center[0] - radius * 0.055, center[1] + radius * 0.30, radius * 0.11, radius * 0.13)
        canvas.ellipse(mouth, fill=palette.outline)
        canvas.ellipse(
            (mouth[0] + radius * 0.025, mouth[1] + radius * 0.035,
             mouth[2] - radius * 0.05, mouth[3] - radius * 0.07),
            fill=palette.inner_ear,
        )
    else:
        smile = BezierPath()
        smile.move_to((center[0], center[1] + radius * 0.24))
        smile.add_line((center[0], center[1] + radius * 0.31))
        canvas.stroke_path(smile, palette.outline, max(radius * 0.035, 1.2), 1.0)
        left = BezierPath()
        left.move_to((center[0], center[1] + radius * 0.31))
        left.add_quad_curve(
            (center[0] - radius * 0.12, center[1] + radius * 0.29),
            (center[0] - radius * 0.07, center[1] + radius * 0.42),
        )
        canvas.stroke_path(left, palette.outline, max(radius * 0.035, 1.2), 1.0)
        right = BezierPath()
        right.move_to((center[0], center[1] + radius * 0.31))
        right.add_quad_curve(
            (center[0] + radius * 0.12, center[1] + radius * 0.29),
            (center[0] + radius * 0.07, center[1] + radius * 0.42),
        )
        canvas.stroke_path(right, palette.outline, max(radius * 0.035, 1.2), 1.0)

    for side in (-1.0, 1.0):
        for offset in (-0.08, 0.04, 0.16):
            start = (center[0] + side * radius * 0.49, center[1] + radius * (0.25 + offset))
            end = (center[0] + side * radius * 0.84, center[1] + radius * (0.18 + offset * 1.8))
            canvas.line([start, end], palette.outline, max(radius * 0.018, 0.7), 0.45)


def draw_kiwi_cheek_heart(canvas: Canvas, head_center, radius: float, time: float,
                          palette: PetPalette, mood: str, animated: bool) -> None:
    if mood != CELEBRATING:
        return
    pulse = 1.0 + 0.08 * math.sin(time * 6.0) if animated else 1.0
    size = radius * 0.16 * pulse
    center = (head_center[0] + radius * 0.52, head_center[1] + radius * 0.33)
    canvas.fill_path(heart(center, size), palette.cheek, 0.85)


def draw_kiwi_paws(canvas: Canvas, center, radius: float, palette: PetPalette, time: float,
                   mood: str, animated: bool) -> None:
    is_moving = mood in (WALKING, DANCING)
    is_waiting = mood == WAITING_FOR_APPROVAL
    step = math.sin(time * (6.2 if mood == DANCING else 8.0)) * radius * 0.065 if (is_moving and animated) else 0.0
    if not animated:
        lift = 0.0
    elif mood == STRETCHING:
        lift = radius * 0.11
    elif mood == DANCING:
        lift = abs(math.sin(time * 6.2)) * radius * 0.12
    else:
        lift = 0.0
    raised_paw = radius * 0.30 if is_waiting else 0.0
    wave = math.sin(time * 3.0) * radius * 0.035 if (is_waiting and animated) else 0.0
    for index, side in enumerate((-1.0, 1.0)):
        offset = step if index == 0 else -step
        is_raised = is_waiting and index == 1
        box = (
            center[0] + side * radius * 0.30 - radius * 0.20 + (-wave * 0.4 if is_raised else 0.0),
            center[1] + radius * 0.70 + offset - lift - (raised_paw + wave if is_raised else 0.0),
            radius * 0.40,
            radius * 0.20,
        )
        canvas.ellipse(box, fill=palette.fur_light)
        canvas.ellipse(box, outline=palette.outline, width=max(radius * 0.025, 0.9), outline_opacity=0.75)


def draw_kiwi_badge(canvas: Canvas, center, radius: float, palette: PetPalette, time: float,
                    mood: str, animated: bool, light: str, agent_count: int) -> None:
    if animated and mood == WORKING:
        pulse = 1 + math.sin(time * 2.8) * 0.035
    elif animated and mood == DANCING:
        pulse = 1 + math.sin(time * 6.2) * 0.085
    else:
        pulse = 1.0
    badge_radius = radius * 0.205 * pulse
    badge_box = (center[0] - badge_radius, center[1] - badge_radius, badge_radius * 2, badge_radius * 2)
    canvas.ellipse(badge_box, fill=palette.accent)
    canvas.ellipse(badge_box, outline=palette.outline, width=max(radius * 0.028, 1.0), outline_opacity=0.76)

    if light != OFF:
        draw_badge(canvas, center, radius, palette.as_dict(), light, agent_count, animated, time)
        return

    core_radius = badge_radius * 0.58
    canvas.ellipse(
        (center[0] - core_radius, center[1] - core_radius, core_radius * 2, core_radius * 2),
        fill=PALE_FILL,
    )
    for index in range(6):
        angle = index * math.pi / 3
        seed_center = (
            center[0] + math.cos(angle) * core_radius * 0.62,
            center[1] + math.sin(angle) * core_radius * 0.62,
        )
        canvas.ellipse(
            (seed_center[0] - radius * 0.018, seed_center[1] - radius * 0.018, radius * 0.036, radius * 0.036),
            fill=palette.outline,
            fill_opacity=0.70,
        )
    canvas.ellipse(
        (center[0] - radius * 0.022, center[1] - radius * 0.022, radius * 0.044, radius * 0.044),
        fill=palette.outline,
        fill_opacity=0.60,
    )


def draw_celebration_effect(canvas: Canvas, center, radius: float, time: float,
                            palette: PetPalette, effect: str) -> None:
    alpha = celebration_alpha(time)
    if alpha <= 0.01:
        return
    fade = alpha / 0.9
    celebration_base(canvas, center, radius, time, palette.as_dict(), fade)
    twinkle = 0.72 + (math.sin(time * 7) + 1) * 0.14

    if effect == "leaves":
        leaves = (
            (-0.84, -0.24, -0.19, -0.39, 0.0),
            (0.82, -0.18, 0.20, -0.39, 1.1),
            (-0.95, 0.30, -0.16, -0.34, 2.2),
            (0.96, 0.32, 0.16, -0.34, 3.3),
            (-0.45, -0.95, -0.10, -0.36, 4.4),
            (0.48, -0.97, 0.10, -0.36, 5.3),
        )
        scales = (0.24, 0.26, 0.21, 0.22, 0.20, 0.23)
        for index, (ax, ay, dx, dy, phase) in enumerate(leaves):
            drift = math.sin(time * 4 + phase) * radius * 0.035
            start = (center[0] + ax * radius, center[1] + ay * radius + drift)
            end = (start[0] + dx * radius, start[1] + dy * radius + drift * 0.5)
            shimmer = 0.82 + 0.18 * (0.5 + 0.5 * math.sin(time * 7 + phase))
            leaf(canvas, start, end, radius * scales[index] * twinkle, palette.accent,
                 min(0.92 * shimmer * fade, 1.0))
    elif effect == "moonDust":
        moon_center = (center[0] + radius * 0.98, center[1] - radius * 0.42)
        moon_pulse = 1.0 + 0.05 * math.sin(time * 5.0 + 0.7)
        canvas.fill_path(
            crescent(moon_center, radius * 0.17 * 1.5 * moon_pulse), palette.accent, min(0.92 * fade, 1.0)
        )
        for index in range(12):
            phase = index * 0.9
            angle = index * math.pi * 2 / 12 + 0.3
            distance = radius * (0.38 + 0.08 * math.sin(time * 2.5 + phase))
            point = (moon_center[0] + math.cos(angle) * distance, moon_center[1] + math.sin(angle) * distance)
            flicker = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(time * 6.0 + phase * 1.7))
            scale = 0.055 + 0.03 * (0.5 + 0.5 * math.sin(phase * 2.3))
            canvas.fill_path(
                star(point, radius * scale * flicker, radius * scale * 0.30),
                palette.fur_light,
                min(0.95 * flicker * fade, 1.0),
            )
    elif effect == "berryHearts":
        for x, y, scale, phase in ((-0.98, -0.42, 0.13, 0.0), (0.98, -0.55, 0.16, 2.1), (-0.89, 0.24, 0.10, 4.2)):
            point = (center[0] + x * radius, center[1] + y * radius)
            beat = 1.0 + 0.10 * math.sin(time * 6.0 + phase)
            canvas.fill_path(
                heart(point, radius * scale * twinkle * beat), palette.cheek, min(0.92 * fade, 1.0)
            )
    elif effect == "starburst":
        for x, y, scale in ((-1.00, -0.48, 0.11), (0.98, -0.53, 0.14), (-0.94, 0.25, 0.085), (0.88, 0.28, 0.09)):
            point = (center[0] + x * radius, center[1] + y * radius)
            canvas.fill_path(
                star(point, radius * scale * twinkle, radius * scale * 0.32),
                palette.accent,
                min(0.95 * fade, 1.0),
            )


def rotate_canvas(image: Image.Image, pivot, cos_sin) -> Image.Image:
    """Rotate a whole canvas about `pivot`; `cos_sin` is (cos, sin) of -angle."""
    c, s = cos_sin
    px, py = pivot
    # dest -> source
    return image.transform(
        image.size,
        Image.AFFINE,
        (c, s, px - c * px - s * py, -s, c, py + s * px - c * py),
        resample=Image.BICUBIC,
        fillcolor=(0, 0, 0, 0),
    )


# ===========================================================================
# SpriteCharacterRenderer.swift - Kot-Arbuz and other layered packs
# ===========================================================================

class SpritePack:
    """The layers and rig of a `pet.json` character pack."""

    def __init__(self, folder: Path) -> None:
        manifest = json.loads((folder / "pet.json").read_text(encoding="utf-8"))
        art = manifest["art"] if "art" in manifest else manifest
        self.canvas = int(art["canvas"])
        self.tail_pivot_x = float(art["tailPivotX"])
        self.tail_pivot_y = float(art["tailPivotY"])
        self.tail_swing_degrees = float(art["tailSwingDegrees"])
        self.rig = art if art.get("format", manifest.get("format", 2)) >= 2 else None
        self.layers = {
            name: Image.open(folder / f"{name}.png").convert("RGBA")
            for name in ("tail", "legs-a", "legs-b", "legs-c", "body", "head")
            if (folder / f"{name}.png").is_file()
        }

    def layer(self, name: str) -> Image.Image:
        return self.layers[name]


def paste_rotated(canvas: Canvas, source: Image.Image, rect, pivot, angle: float) -> None:
    """Draw `source` placed in `rect`, rotated by `angle` about `pivot`."""
    x0, y0, w, h = rect
    side = source.size[0]
    c, s = math.cos(angle), math.sin(angle)
    coeffs = (
        (side / w) * c,
        (side / w) * s,
        (side / w) * (pivot[0] - c * pivot[0] - s * pivot[1] - x0),
        (side / h) * (-s),
        (side / h) * c,
        (side / h) * (s * pivot[0] - c * pivot[1] + pivot[1] - y0),
    )
    corners = [(x0, y0), (x0 + w, y0), (x0 + w, y0 + h), (x0, y0 + h)]
    rotated = [rotate_point(point, pivot, (c, s)) for point in corners]
    box = (
        min(p[0] for p in rotated),
        min(p[1] for p in rotated),
        max(p[0] for p in rotated),
        max(p[1] for p in rotated),
    )
    canvas.draw_affine(source, rect, coeffs, box)


def paste_scaled_y(canvas: Canvas, source: Image.Image, rect, pivot_y: float, scale_y: float) -> None:
    x0, y0, w, h = rect
    side = source.size[0]
    coeffs = (
        side / w,
        0.0,
        -(side / w) * x0,
        0.0,
        (side / h) / scale_y,
        (side / h) * (pivot_y - pivot_y / scale_y - y0),
    )
    top = pivot_y + (y0 - pivot_y) * scale_y
    bottom = pivot_y + (y0 + h - pivot_y) * scale_y
    canvas.draw_affine(source, rect, coeffs, (x0, min(top, bottom), x0 + w, max(top, bottom)))


def paste_head(canvas: Canvas, source: Image.Image, rect, pivot, angle: float, lift: float) -> None:
    """The head layer: translate by `lift`, then rotate about `pivot`."""
    x0, y0, w, h = rect
    side = source.size[0]
    c, s = math.cos(angle), math.sin(angle)
    coeffs = (
        (side / w) * c,
        (side / w) * s,
        (side / w) * (pivot[0] - c * pivot[0] - s * pivot[1] - s * lift - x0),
        (side / h) * (-s),
        (side / h) * c,
        (side / h) * (pivot[1] + s * pivot[0] - c * pivot[1] - c * lift - y0),
    )
    corners = [(x0, y0), (x0 + w, y0), (x0 + w, y0 + h), (x0, y0 + h)]
    moved = [(p[0], rotate_point(p, pivot, (c, s))[1] + lift) for p in corners]
    box = (
        min(p[0] for p in moved) - 2,
        min(p[1] for p in moved) - 2,
        max(p[0] for p in moved) + 2,
        max(p[1] for p in moved) + 2,
    )
    canvas.draw_affine(source, rect, coeffs, box)


def rig_pose(mood: str, time: float, animated: bool) -> dict:
    """`SpriteCharacterRenderer.rigPose`."""
    pose = {"headAngle": 0.0, "headLift": 0.0, "legA": 0.0, "legB": 0.0, "legC": 0.0, "eyes": "open"}

    def calm_tilt(amplitude: float) -> float:
        if not animated:
            return 0.0
        period = 18.0
        phase = time % period
        if not (0.0 <= phase < 2.0):
            return 0.0
        t = phase / 2.0
        envelope = smoothstep(0, 0.4, t) * (1 - smoothstep(0.6, 1.0, t))
        direction = 1.0 if int(math.floor(time / period)) % 2 == 0 else -1.0
        return direction * amplitude * envelope

    d = math.pi / 180
    if mood == IDLE:
        pose["headLift"] = math.sin(time * 1.45) * 0.006 if animated else 0.0
        pose["headAngle"] = calm_tilt(2.0 * d)
    elif mood == WORKING:
        pose["headLift"] = math.sin(time * 1.9) * 0.005 if animated else 0.0
        pose["headAngle"] = calm_tilt(1.4 * d)
    elif mood == CELEBRATING:
        pose["headAngle"] = math.sin(time * 6.2) * 2.4 * d if animated else 0.0
        pose["headLift"] = -abs(math.sin(time * 3.1)) * 0.010 if animated else -0.006
        pose["legA"] = math.sin(time * 6.2) * 4 * d if animated else 0.0
        pose["legC"] = pose["legA"]
        pose["legB"] = -pose["legA"]
        pose["eyes"] = "happy"
    elif mood == DANCING:
        pose["headAngle"] = math.sin(time * 6.2) * 3 * d if animated else 0.0
        pose["headLift"] = -abs(math.sin(time * 6.2)) * 0.012 if animated else 0.0
        pose["legA"] = math.sin(time * 6.2) * 5 * d if animated else 0.0
        pose["legC"] = pose["legA"]
        pose["legB"] = -pose["legA"]
        pose["eyes"] = "happy"
    elif mood == STRETCHING:
        pose["headAngle"] = -2.0 * d
        pose["headLift"] = -0.008
        pose["legA"] = 6.0 * d
        pose["legC"] = -6.0 * d
        pose["eyes"] = "half"
    elif mood == CURIOUS:
        pose["headAngle"] = 3.0 * d + (math.sin(time * 2.2) * 0.6 * d if animated else 0.0)
        pose["eyes"] = "wide"
    elif mood == BREAK_REMINDER:
        pose["headAngle"] = -2.0 * d
        pose["headLift"] = 0.004
        pose["eyes"] = "half"
    elif mood == RESTING:
        pose["headAngle"] = 1.5 * d
        pose["headLift"] = 0.010
        pose["legA"] = -3.0 * d
        pose["legC"] = -3.0 * d
        pose["legB"] = 3.0 * d
        pose["eyes"] = "closed"
    elif mood == DRAGGING:
        pose["headAngle"] = math.sin(time * 9) * 1.5 * d if animated else 0.0
        pose["legA"] = math.sin(time * 9) * 7 * d if animated else 0.0
        pose["legC"] = -math.sin(time * 9) * 7 * d if animated else 0.0
        pose["legB"] = math.sin(time * 9 + 1.0) * 5 * d if animated else 0.0
        pose["eyes"] = "wide"
    elif mood == WALKING:
        pose["headLift"] = abs(math.sin(time * 8)) * 0.004 if animated else 0.0
        pose["legA"] = math.sin(time * 8) * 6 * d if animated else 0.0
        pose["legC"] = pose["legA"]
        pose["legB"] = -pose["legA"]
    elif mood == WAITING_FOR_APPROVAL:
        pose["headAngle"] = 1.5 * d
        pose["headLift"] = -0.010
        pose["eyes"] = "wide"

    if animated and pose["eyes"] in ("open", "wide") and (time % 4.6) < 0.14:
        pose["eyes"] = "closed"
    return pose


def draw_sprite_eyes(canvas: Canvas, rect, rig, palette: PetPalette, gaze, state: str) -> None:
    """Vector eyes at the rig's socket anchors (`drawEyes`)."""
    for socket in ((float(rig["eyeLeftX"]), float(rig["eyeLeftY"])), (float(rig["eyeRightX"]), float(rig["eyeRightY"]))):
        center = (rect[0] + socket[0] * rect[2], rect[1] + socket[1] * rect[3])
        radius_x = float(rig["eyeRadiusX"]) * rect[2]
        radius_y = float(rig["eyeRadiusY"]) * rect[3]
        gaze_x = gaze[0] * radius_x * 0.42
        gaze_y = gaze[1] * radius_y * 0.38

        if state in ("closed", "happy"):
            arc = closed_eye_path(center, radius_x, state == "happy")
            canvas.stroke_path(arc, palette.outline, max(radius_x * 0.62, 1.2))
        elif state == "half":
            canvas.ellipse(
                (center[0] - radius_x + gaze_x, center[1] - radius_y * 0.28 + gaze_y, radius_x * 2, radius_y * 1.1),
                fill=palette.outline,
            )
            canvas.line(
                [
                    (center[0] - radius_x * 1.12 + gaze_x, center[1] - radius_y * 0.28 + gaze_y),
                    (center[0] + radius_x * 1.12 + gaze_x, center[1] - radius_y * 0.28 + gaze_y),
                ],
                palette.outline,
                max(radius_x * 0.42, 1.0),
            )
        else:
            scale = 1.18 if state == "wide" else 1.0
            canvas.ellipse(
                (
                    center[0] - radius_x * scale + gaze_x,
                    center[1] - radius_y * scale + gaze_y,
                    radius_x * 2 * scale,
                    radius_y * 2 * scale,
                ),
                fill=palette.outline,
            )
            shine = radius_x * 0.30 * scale
            canvas.ellipse(
                (
                    center[0] - radius_x * 0.34 * scale + gaze_x * 0.8 - shine / 2,
                    center[1] - radius_y * 0.42 * scale + gaze_y * 0.8 - shine / 2,
                    shine,
                    shine,
                ),
                fill=(255, 255, 255),
                fill_opacity=0.92,
            )


def draw_sprite_halo(canvas: Canvas, center, radius: float, palette: PetPalette, mood: str) -> None:
    is_waiting = mood == WAITING_FOR_APPROVAL
    if mood not in (WORKING, CELEBRATING, DANCING, BREAK_REMINDER, WAITING_FOR_APPROVAL):
        return
    if mood in (CELEBRATING, DANCING):
        opacity = 0.15
    elif mood in (BREAK_REMINDER, WAITING_FOR_APPROVAL):
        opacity = 0.13
    else:
        opacity = 0.08
    color = WAITING_COLOR if is_waiting else palette.accent
    canvas.ellipse(
        (center[0] - radius * 1.16, center[1] - radius * 0.98, radius * 2.32, radius * 2.32),
        fill=color,
        fill_opacity=opacity,
    )


def draw_petting_hearts(canvas: Canvas, rect, time: float, palette: PetPalette, animated: bool) -> None:
    for x, y, scale, phase in ((0.34, 0.30, 0.115, 0.0), (0.46, 0.16, 0.075, 1.3), (0.24, 0.14, 0.058, 2.4)):
        beat = 1.0 + 0.10 * math.sin(time * 6.0 + phase) if animated else 1.0
        center = (rect[0] + rect[2] * (0.5 + x), rect[1] + rect[3] * (0.5 + y))
        canvas.fill_path(heart(center, rect[2] * scale * beat), palette.cheek, 0.85)


def draw_sprite_celebration(canvas: Canvas, center, radius: float, time: float,
                            palette: PetPalette, animated: bool) -> None:
    alpha = celebration_alpha(time, not animated)
    if alpha <= 0.01:
        return
    fade = alpha / 0.9
    celebration_base(canvas, center, radius, time, palette.as_dict(), fade)
    twinkle = 0.72 + (math.sin(time * 7) + 1) * 0.14 if animated else 0.86

    effect = palette.celebration_effect
    if effect == "leaves":
        for x, y, scale, phase in (
            (-0.72, -0.30, 0.20, 0.0), (0.70, -0.34, 0.20, 1.1), (-0.80, 0.22, 0.18, 2.2),
            (0.82, 0.20, 0.18, 3.3), (-0.36, -0.78, 0.16, 4.4), (0.38, -0.80, 0.16, 5.3),
        ):
            drift = math.sin(time * 4 + phase) * radius * 0.035 if animated else 0.0
            start = (center[0] + x * radius, center[1] + y * radius + drift)
            end = (start[0] - radius * 0.14, start[1] - radius * 0.26)
            shimmer = 0.82 + 0.18 * (0.5 + 0.5 * math.sin(time * 7 + phase)) if animated else 1.0
            leaf(canvas, start, end, radius * scale * twinkle, palette.accent, min(0.92 * shimmer * fade, 1.0))
    elif effect == "moonDust":
        moon_center = (center[0] + radius * 0.92, center[1] - radius * 0.40)
        canvas.fill_path(crescent(moon_center, radius * 0.24), palette.accent, min(0.92 * fade, 1.0))
        for index in range(12):
            phase = index * 0.9
            angle = index * math.pi * 2 / 12 + 0.3
            distance = radius * (0.36 + 0.08 * math.sin(time * 2.5 + phase)) if animated else radius * 0.36
            point = (moon_center[0] + math.cos(angle) * distance, moon_center[1] + math.sin(angle) * distance)
            flicker = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(time * 6.0 + phase * 1.7)) if animated else 1.0
            canvas.fill_path(
                star(point, radius * 0.06 * flicker, radius * 0.018 * flicker),
                palette.fur_light,
                min(0.95 * flicker * fade, 1.0),
            )
    elif effect == "berryHearts":
        for x, y, scale, phase in ((-0.72, -0.36, 0.14, 0.0), (0.74, -0.46, 0.17, 2.1), (-0.66, 0.20, 0.11, 4.2)):
            point = (center[0] + x * radius, center[1] + y * radius)
            beat = 1.0 + 0.10 * math.sin(time * 6.0 + phase) if animated else 1.0
            canvas.fill_path(heart(point, radius * scale * twinkle * beat), palette.cheek, min(0.92 * fade, 1.0))
    elif effect == "starburst":
        for x, y, scale in ((-0.76, -0.42, 0.12), (0.74, -0.46, 0.15), (-0.70, 0.22, 0.09), (0.66, 0.24, 0.10)):
            point = (center[0] + x * radius, center[1] + y * radius)
            canvas.fill_path(
                star(point, radius * scale * twinkle, radius * scale * 0.32), palette.accent, min(0.95 * fade, 1.0)
            )


def draw_sprite(canvas: Canvas, size, time: float, mood: str, palette: PetPalette, pack: SpritePack,
                light: str, agent_count: int, attention, gaze, animated: bool = True) -> None:
    """Port of `SpriteCharacterRenderer.draw`."""
    width, height = size
    side = height * 0.88
    feet = (width * 0.5, height * 0.862)
    rect = (feet[0] - side / 2, feet[1] - side, side, side)
    pet_radius = min(width, height) * 0.335

    feed_bounce = mood == WORKING or light == LIGHT_WORKING
    is_dancing = mood == DANCING and animated
    is_celebrating = mood == CELEBRATING
    is_waiting = mood == WAITING_FOR_APPROVAL
    dance_sway = math.sin(time * 6.2) * 3.2 if is_dancing else 0.0
    walk_sway = math.sin(time * 8) * 2.0 if (mood == WALKING and animated) else 0.0
    lean = dance_sway + walk_sway + (-2.4 if is_waiting else 0.0) + (1.4 if mood == CURIOUS else 0.0)
    if not animated:
        hop = 0.0
    elif is_dancing:
        hop = abs(math.sin(time * 6.2)) * side * 0.020
    elif is_celebrating:
        hop = abs(math.sin(time * 3.1)) * side * 0.028
    elif feed_bounce:
        hop = abs(math.sin(time * 2.4)) * side * 0.010
    else:
        hop = 0.0

    breath_frequency = palette.breathing_frequency * (1.25 if light == LIGHT_WORKING else 1.0)
    breath = math.sin(time * breath_frequency) * palette.breathing_amplitude if animated else 0.0
    stretch = 0.05 if (mood == STRETCHING and animated) else 0.0

    # The halo is drawn before the lean/hop transform, exactly as in SwiftUI,
    # where `translateBy`/`concatenate` only affect later draws.
    draw_sprite_halo(
        canvas,
        (rect[0] + rect[2] / 2, rect[1] + rect[3] * 0.56),
        side * 0.52,
        palette,
        mood,
    )

    pet = Canvas((width, height))
    tail_pivot = (rect[0] + pack.tail_pivot_x * rect[2], rect[1] + pack.tail_pivot_y * rect[3])
    if is_dancing:
        swing_scale = 2.0
    elif is_waiting:
        swing_scale = 1.5
    elif mood == WORKING or light == LIGHT_WORKING:
        swing_scale = 1.2
    elif mood == RESTING:
        swing_scale = 0.5
    else:
        swing_scale = 1.0
    base_swing = math.sin(time * palette.tail_frequency) * pack.tail_swing_degrees * swing_scale if animated else 0.0
    raised_lift = -7.0 if is_waiting else (8.0 if is_dancing else (3.0 if feed_bounce else 0.0))
    tail_angle = radians(base_swing + raised_lift)

    pose = rig_pose(mood, time, animated)
    rig = pack.rig
    if rig is not None and all(name in pack.layers for name in ("head", "legs-a", "legs-b", "legs-c")):
        legs = (
            ("legs-a", (rect[0] + float(rig["legPivotAX"]) * rect[2], rect[1] + float(rig["legPivotAY"]) * rect[3]), pose["legA"]),
            ("legs-b", (rect[0] + float(rig["legPivotBX"]) * rect[2], rect[1] + float(rig["legPivotBY"]) * rect[3]), pose["legB"]),
            ("legs-c", (rect[0] + float(rig["legPivotCX"]) * rect[2], rect[1] + float(rig["legPivotCY"]) * rect[3]), pose["legC"]),
        )
        for name, pivot, angle in legs:
            paste_rotated(pet, pack.layer(name), rect, pivot, angle)

    paste_rotated(pet, pack.layer("tail"), rect, tail_pivot, tail_angle)
    paste_scaled_y(pet, pack.layer("body"), rect, feet[1], 1.0 + breath * 1.6 + stretch)

    if rig is not None and "head" in pack.layers:
        head_pivot = (rect[0] + float(rig["headPivotX"]) * rect[2], rect[1] + float(rig["headPivotY"]) * rect[3])
        # The head carries the vector eyes, so both share one transform. They are
        # composed on a sub-canvas the size of the sprite box first: `paste_head`
        # maps destination pixels back into the source image, so that image has to
        # cover exactly the box it is placed in.
        sub_side = int(round(rect[2]))
        sub_rect = (0.0, 0.0, float(sub_side), float(sub_side))
        head_layer = Canvas((sub_side, sub_side))
        paste_rotated(head_layer, pack.layer("head"), sub_rect, (0.0, 0.0), 0.0)
        draw_sprite_eyes(head_layer, sub_rect, rig, palette, gaze, pose["eyes"])
        paste_head(
            pet,
            head_layer.image,
            (rect[0], rect[1], float(sub_side), float(sub_side)),
            head_pivot,
            pose["headAngle"],
            pose["headLift"] * side,
        )

    if is_celebrating:
        draw_petting_hearts(pet, rect, time, palette, animated)
    if animated and (is_celebrating or is_dancing):
        draw_sprite_celebration(
            pet, (rect[0] + rect[2] / 2, rect[1] + rect[3] * 0.5), side * 0.44, time, palette, animated
        )
    if mood in (CURIOUS, BREAK_REMINDER):
        sparkle = (rect[0] + rect[2] - side * 0.16, rect[1] + side * 0.20)
        pet.fill_path(star(sparkle, side * 0.05, side * 0.021), palette.accent, 0.90)

    draw_badge(
        pet,
        (rect[0] + rect[2] / 2, rect[1] + rect[3] * 0.70),
        pet_radius,
        palette.as_dict(),
        light,
        agent_count,
        animated,
        time,
    )
    if attention is not None:
        draw_glyph_badge(pet, (width * 0.5, height * 0.105), min(width, height) * 0.16, attention)

    if animated:
        c, s = math.cos(radians(lean)), math.sin(radians(lean))
        transformed = pet.image.transform(
            pet.size,
            Image.AFFINE,
            (
                c,
                s,
                feet[0] - c * feet[0] - s * feet[1] + s * hop,
                -s,
                c,
                feet[1] + s * feet[0] - c * feet[1] + c * hop,
            ),
            resample=Image.BICUBIC,
            fillcolor=(0, 0, 0, 0),
        )
        canvas.paste(transformed, (0, 0))
    else:
        canvas.paste(pet.image, (0, 0))


# ===========================================================================
# timeline, export, CLI
# ===========================================================================

# label, mood, seconds, agent light, session count, attention symbol, time offset.
# The offsets place each shot's phase so the interesting beat lands mid-shot:
# idle starts 1.2 s before a blink (the cadence is one blink every 4.6 s), and
# walk/waiting dodge the blink window so their eyes stay open.
SHOTS = (
    ("idle", IDLE, 3.0, OFF, 0, None, 44.8),
    ("walk", WALKING, 2.4, OFF, 0, None, 1.0),
    ("dance", DANCING, 2.4, OFF, 0, None, 0.0),
    ("hearts", CELEBRATING, 2.4, OFF, 0, None, 0.0),
    ("waiting", WAITING_FOR_APPROVAL, 2.4, LIGHT_WAITING, 2, "question", 0.5),
    ("celebration", CELEBRATING, 2.4, LIGHT_WORKING, 3, None, 0.0),
)

CATS = {
    "kot-arbuz": {"skin": "kot-arbuz", "pack": True},
    "kiwi": {"skin": "kiwi", "pack": False},
}


def gaze_at(time: float):
    """A synthetic cursor path, so the eyes visibly track something."""
    return (
        clamp(0.92 * math.sin(time * 0.85), -1.0, 1.0),
        clamp(0.62 * math.sin(time * 0.53 + 1.0), -1.0, 1.0),
    )


def shot_at(elapsed: float):
    """Return (shot, local time) for a position in the loop."""
    cursor = 0.0
    for shot in SHOTS:
        if elapsed < cursor + shot[2] or shot is SHOTS[-1]:
            return shot, elapsed - cursor
        cursor += shot[2]
    return SHOTS[-1], elapsed - cursor


def render_frame(size, elapsed: float, palette: PetPalette, pack, animated: bool = True) -> Image.Image:
    shot, local = shot_at(elapsed)
    _, mood, _, light, count, attention, offset = shot
    time = local + offset
    canvas = Canvas(size)
    if pack is None:
        draw_kiwi(canvas, size, time, mood, palette, gaze_at(elapsed), light, count, attention, animated)
    else:
        draw_sprite(canvas, size, time, mood, palette, pack, light, count, attention, gaze_at(elapsed), animated)
    return canvas.image


def premultiplied_resize(image: Image.Image, size) -> Image.Image:
    """Downscale RGBA after premultiplying, so transparent edges stay clean."""
    array = np.asarray(image).astype(np.float32)
    alpha = array[:, :, 3:4] / 255.0
    array[:, :, :3] *= alpha
    premultiplied = Image.fromarray(array.astype(np.uint8), "RGBA").resize(size, Image.LANCZOS)
    out = np.asarray(premultiplied).astype(np.float32)
    out_alpha = out[:, :, 3:4] / 255.0
    out[:, :, :3] = np.divide(out[:, :, :3], out_alpha, out=np.zeros_like(out[:, :, :3]), where=out_alpha > 0)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def render_cat(name: str, outdir: Path) -> list[Path]:
    config = CATS[name]
    palette = load_palette(config["skin"])
    pack = SpritePack(SKIN_ROOT / config["skin"]) if config["pack"] else None
    render_size = (OUTPUT * SS, OUTPUT * SS)
    duration_ms = int(round(1000.0 / FPS))

    frames: list[Image.Image] = []
    for index in range(FRAMES):
        elapsed = index / FPS
        frame = render_frame(render_size, elapsed, palette, pack)
        frames.append(premultiplied_resize(frame, (OUTPUT, OUTPUT)))

    written: list[Path] = []
    webp_path = outdir / f"animation-{name}.webp"
    frames[0].save(
        webp_path,
        save_all=True,
        append_images=frames[1:],
        duration=duration_ms,
        loop=0,
        quality=62,
        method=4,
    )
    written.append(webp_path)

    gif_path = outdir / f"animation-{name}.gif"
    save_gif(frames, gif_path, duration_ms)
    written.append(gif_path)
    return written


def save_gif(frames: list[Image.Image], path: Path, duration_ms: int) -> None:
    """Animated GIF with a single shared palette and one transparent index."""
    samples = []
    for frame in frames[::4]:
        array = np.asarray(frame)
        samples.append(array[:, :, :3][array[:, :, 3] > 200])
    stack = np.concatenate(samples)[:, None, :] if samples else np.zeros((1, 1, 3), dtype=np.uint8)
    if stack.shape[0] > 200_000:
        index = np.random.default_rng(7).choice(stack.shape[0], 200_000, replace=False)
        stack = stack[index]
    palette_image = Image.fromarray(stack, "RGB").quantize(colors=128, method=Image.MAXCOVERAGE)
    palette = palette_image.getpalette()

    out_frames = []
    for frame in frames:
        quantized = np.array(frame.convert("RGB").quantize(palette=palette_image, dither=Image.FLOYDSTEINBERG))
        alpha = np.asarray(frame.getchannel("A"))
        quantized[alpha < 128] = 255
        image = Image.fromarray(quantized, "P")
        image.putpalette(palette)
        out_frames.append(image)

    out_frames[0].save(
        path,
        save_all=True,
        append_images=out_frames[1:],
        duration=duration_ms,
        loop=0,
        optimize=True,
        transparency=255,
        disposal=2,
    )


def check(outdir: Path) -> int:
    expected = [outdir / f"animation-{name}.{suffix}" for name in CATS for suffix in ("webp", "gif")]
    if not any(path.is_file() for path in expected):
        print("SKIP character animation check: no rendered loops in " + str(outdir))
        return 0

    errors = []
    for name in CATS:
        for suffix in ("webp", "gif"):
            path = outdir / f"animation-{name}.{suffix}"
            if not path.is_file():
                errors.append(f"missing rendered loop: {path.name}")
                continue
            with Image.open(path) as image:
                if image.size != (OUTPUT, OUTPUT):
                    errors.append(f"{path.name}: size {image.size}, expected {(OUTPUT, OUTPUT)}")
                if image.n_frames != FRAMES:
                    errors.append(f"{path.name}: {image.n_frames} frames, expected {FRAMES}")
                first = image.convert("RGBA").getchannel("A")
                if first.getextrema()[0] != 0:
                    errors.append(f"{path.name}: the background is not transparent")
            size_kb = path.stat().st_size / 1024
            print(f"{path.name}: {OUTPUT}x{OUTPUT}, {FRAMES} frames, {size_kb:.0f} KB")
    if errors:
        for error in errors:
            print(f"::error title=Character animations::{error}")
        return 1
    print(f"Character animation check passed: {len(CATS)} cats, transparent {OUTPUT}x{OUTPUT} loops.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Render transparent animation loops of both cats.")
    parser.add_argument("--cat", choices=sorted(CATS), help="render a single cat")
    parser.add_argument("--outdir", type=Path, default=OUT_DIR)
    parser.add_argument("--check", action="store_true", help="verify the rendered loops instead of rendering")
    args = parser.parse_args()

    args.outdir.mkdir(parents=True, exist_ok=True)
    if args.check:
        return check(args.outdir)

    names = [args.cat] if args.cat else list(CATS)
    for name in names:
        written = render_cat(name, args.outdir)
        for path in written:
            print(f"wrote {path.relative_to(ROOT)} ({path.stat().st_size / 1024:.0f} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
