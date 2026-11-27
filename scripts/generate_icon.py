#!/usr/bin/env python3
import math
import os
import struct
import subprocess
import zlib


def write_png(path, width, height, rgba_bytes):
    def chunk(tag, data):
        return struct.pack("!I", len(data)) + tag + data + struct.pack("!I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw_rows = bytearray()
    stride = width * 4
    for y in range(height):
        raw_rows.append(0)
        start = y * stride
        raw_rows.extend(rgba_bytes[start : start + stride])

    ihdr = struct.pack("!IIBBBBB", width, height, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(raw_rows), 9)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def clamp01(v):
    return 0.0 if v < 0.0 else (1.0 if v > 1.0 else v)


def smoothstep(edge0, edge1, x):
    t = clamp01((x - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    return a + (b - a) * t


def blend_pixel(dst_r, dst_g, dst_b, dst_a, src_r, src_g, src_b, src_a):
    inv = 1.0 - src_a
    out_a = src_a + dst_a * inv
    if out_a <= 1e-6:
        return 0.0, 0.0, 0.0, 0.0
    out_r = (src_r * src_a + dst_r * dst_a * inv) / out_a
    out_g = (src_g * src_a + dst_g * dst_a * inv) / out_a
    out_b = (src_b * src_a + dst_b * dst_a * inv) / out_a
    return out_r, out_g, out_b, out_a


def sd_squircle(px, py, cx, cy, half_size, radius):
    dx = abs(px - cx) - (half_size - radius)
    dy = abs(py - cy) - (half_size - radius)
    qx = max(dx, 0.0)
    qy = max(dy, 0.0)
    return math.hypot(qx, qy) + min(max(dx, dy), 0.0) - radius


def dist_segment(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    vv = vx * vx + vy * vy
    if vv <= 1e-9:
        return math.hypot(px - ax, py - ay)
    t = clamp01((wx * vx + wy * vy) / vv)
    proj_x = ax + t * vx
    proj_y = ay + t * vy
    return math.hypot(px - proj_x, py - proj_y)


def render_icon(size=512):
    buf = bytearray(size * size * 4)
    cx = size * 0.5
    cy = size * 0.5
    half = size * 0.415
    corner = size * 0.19

    dial_cx = cx
    dial_cy = cy + size * 0.03
    arc_r = size * 0.255
    arc_thickness = size * 0.036

    # 晴雨表弧线（顶部开口向上，-215 deg 到 +35 deg，在屏幕坐标系中 y 向下）
    start_deg = 145.0
    end_deg = 395.0
    needle_angle = math.radians(312.0)  # 指向右上偏舒适区间
    nx = dial_cx + math.cos(needle_angle) * (arc_r * 0.84)
    ny = dial_cy + math.sin(needle_angle) * (arc_r * 0.84)
    tail_x = dial_cx - math.cos(needle_angle) * (size * 0.055)
    tail_y = dial_cy - math.sin(needle_angle) * (size * 0.055)

    for y in range(size):
        for x in range(size):
            px = x + 0.5
            py = y + 0.5
            d_box = sd_squircle(px, py, cx, cy, half, corner)
            if d_box > 1.5:
                continue

            base_alpha = 1.0 - smoothstep(-1.0, 1.0, d_box)

            # 深邃液态玻璃海蓝-石青渐变背景
            ny_norm = clamp01((py - (cy - half)) / (2.0 * half))
            nx_norm = clamp01((px - (cx - half)) / (2.0 * half))
            bg_r = mix(14.0, 26.0, ny_norm) + 12.0 * (1.0 - nx_norm) * (1.0 - ny_norm)
            bg_g = mix(42.0, 88.0, 1.0 - ny_norm * 0.65) + 16.0 * nx_norm * (1.0 - ny_norm)
            bg_b = mix(76.0, 148.0, 1.0 - ny_norm * 0.4)

            # 顶部玻璃高光反射
            glow = math.exp(-((px - cx) ** 2 / (size * 0.28) ** 2 + (py - (cy - half * 0.55)) ** 2 / (size * 0.18) ** 2))
            bg_r = min(255.0, bg_r + glow * 34.0)
            bg_g = min(255.0, bg_g + glow * 48.0)
            bg_b = min(255.0, bg_b + glow * 54.0)

            r, g, b, a = bg_r / 255.0, bg_g / 255.0, bg_b / 255.0, base_alpha

            # 内圈细高光描边
            if -2.5 < d_box <= 0.5:
                rim_a = (1.0 - abs(d_box + 0.6) / 1.5) * 0.35 * (1.0 - ny_norm * 0.6)
                if rim_a > 0:
                    r, g, b, a = blend_pixel(r, g, b, a, 1.0, 1.0, 1.0, rim_a)

            # 晴雨表渐变刻度弧
            dx = px - dial_cx
            dy = py - dial_cy
            dist_c = math.hypot(dx, dy)
            ang = math.degrees(math.atan2(dy, dx))
            if ang < 100.0:
                ang += 360.0

            if start_deg - 4.0 <= ang <= end_deg + 4.0:
                d_arc = abs(dist_c - arc_r) - arc_thickness * 0.5
                if d_arc < 1.5:
                    arc_a = 1.0 - smoothstep(-0.8, 0.9, d_arc)
                    t_ang = clamp01((ang - start_deg) / (end_deg - start_deg))
                    if t_ang < 0.55:
                        # 青绿到天蓝
                        ar = mix(0.24, 0.30, t_ang / 0.55)
                        ag = mix(0.84, 0.92, t_ang / 0.55)
                        ab = mix(0.96, 0.62, t_ang / 0.55)
                    else:
                        # 翠绿到暖琥珀
                        k = (t_ang - 0.55) / 0.45
                        ar = mix(0.30, 1.00, k)
                        ag = mix(0.92, 0.66, k)
                        ab = mix(0.62, 0.24, k)
                    r, g, b, a = blend_pixel(r, g, b, a, ar, ag, ab, arc_a * 0.95)

            # 极简表盘指针
            d_needle = dist_segment(px, py, tail_x, tail_y, nx, ny) - size * 0.017
            if d_needle < 1.5:
                na = 1.0 - smoothstep(-0.8, 0.9, d_needle)
                r, g, b, a = blend_pixel(r, g, b, a, 0.98, 0.99, 1.0, na)

            # 中心枢纽圆点
            d_hub = dist_c - size * 0.036
            if d_hub < 1.5:
                ha = 1.0 - smoothstep(-0.8, 0.9, d_hub)
                r, g, b, a = blend_pixel(r, g, b, a, 1.0, 1.0, 1.0, ha)

            idx = (y * size + x) * 4
            buf[idx] = int(clamp01(r) * 255)
            buf[idx + 1] = int(clamp01(g) * 255)
            buf[idx + 2] = int(clamp01(b) * 255)
            buf[idx + 3] = int(clamp01(a) * 255)

    return buf


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    build_dir = os.path.join(root, "dist", "icon_build")
    iconset_dir = os.path.join(build_dir, "AppIcon.iconset")
    os.makedirs(iconset_dir, exist_ok=True)

    master_png = os.path.join(build_dir, "master_512.png")
    rgba = render_icon(512)
    write_png(master_png, 512, 512, rgba)

    sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    for filename, px in sizes:
        out_path = os.path.join(iconset_dir, filename)
        subprocess.run(
            ["sips", "-z", str(px), str(px), master_png, "--out", out_path],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    icns_path = os.path.join(root, "dist", "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", icns_path], check=True)
    print(f"Generated {icns_path}")


if __name__ == "__main__":
    main()
