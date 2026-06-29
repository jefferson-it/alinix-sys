#!/usr/bin/env python3
"""
Builds AlinixLogo-Regular.otf
- U+E000 (PUA) → Alinix logo glyph from logo.svg
"""

import math
import xml.etree.ElementTree as ET
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.misc.psCharStrings import T2CharString

VIEWBOX = 512
UPM = 1000

def sx(x): return x * UPM / VIEWBOX
def sy(y): return (VIEWBOX - y) * UPM / VIEWBOX   # flip Y


# ── geometry helpers ────────────────────────────────────────────────────────

def draw_circle(cx, cy, r, pen):
    k = 0.5522847498
    cx, cy, r = sx(cx), sy(cy), r * UPM / VIEWBOX
    pen.moveTo((cx + r, cy))
    pen.curveTo((cx + r, cy + k*r), (cx + k*r, cy + r), (cx, cy + r))
    pen.curveTo((cx - k*r, cy + r), (cx - r, cy + k*r), (cx - r, cy))
    pen.curveTo((cx - r, cy - k*r), (cx - k*r, cy - r), (cx, cy - r))
    pen.curveTo((cx + k*r, cy - r), (cx + r, cy - k*r), (cx + r, cy))
    pen.closePath()


def arc_beziers(x1, y1, rx, ry, x_rot, large, sweep, x2, y2):
    """SVG arc segment → list of cubic bezier tuples (p1x,p1y, p2x,p2y, ex,ey)."""
    if x1 == x2 and y1 == y2:
        return []
    phi = math.radians(x_rot)
    cos_phi, sin_phi = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p =  cos_phi*dx + sin_phi*dy
    y1p = -sin_phi*dx + cos_phi*dy
    x1p2, y1p2 = x1p**2, y1p**2
    rx2, ry2 = rx**2, ry**2
    lam = x1p2/rx2 + y1p2/ry2
    if lam > 1:
        lam = math.sqrt(lam); rx *= lam; ry *= lam; rx2 = rx**2; ry2 = ry**2
    num = max(0.0, rx2*ry2 - rx2*y1p2 - ry2*x1p2)
    den = rx2*y1p2 + ry2*x1p2
    sq = (math.sqrt(num/den) if den else 0) * (-1 if large == sweep else 1)
    cxp =  sq*rx*y1p/ry
    cyp = -sq*ry*x1p/rx
    mx, my = (x1+x2)/2, (y1+y2)/2
    cx = cos_phi*cxp - sin_phi*cyp + mx
    cy = sin_phi*cxp + cos_phi*cyp + my

    def vangle(ux, uy, vx, vy):
        n = math.sqrt(ux**2+uy**2)*math.sqrt(vx**2+vy**2)
        c = max(-1, min(1, (ux*vx+uy*vy)/n)) if n else 1
        a = math.acos(c)
        return a if ux*vy - uy*vx >= 0 else -a

    theta1 = vangle(1, 0, (x1p-cxp)/rx, (y1p-cyp)/ry)
    dtheta = vangle((x1p-cxp)/rx, (y1p-cyp)/ry, (-x1p-cxp)/rx, (-y1p-cyp)/ry)
    if not sweep and dtheta > 0: dtheta -= 2*math.pi
    elif sweep and dtheta < 0:   dtheta += 2*math.pi

    n = max(1, math.ceil(abs(dtheta)/(math.pi/2)))
    out = []
    for i in range(n):
        t1 = theta1 + i*dtheta/n
        t2 = theta1 + (i+1)*dtheta/n
        dt = t2 - t1
        alpha = math.sin(dt)*(math.sqrt(4+3*math.tan(dt/2)**2)-1)/3
        p1x = cx + rx*(math.cos(t1) - alpha*math.sin(t1))
        p1y = cy + ry*(math.sin(t1) + alpha*math.cos(t1))
        p2x = cx + rx*(math.cos(t2) + alpha*math.sin(t2))
        p2y = cy + ry*(math.sin(t2) - alpha*math.cos(t2))
        ex  = cx + rx*math.cos(t2)
        ey  = cy + ry*math.sin(t2)
        out.append((p1x, p1y, p2x, p2y, ex, ey))
    return out


def tokenize_d(d):
    import re
    return re.findall(r'[MmLlCcQqZzAaSsHhVv]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?', d)


def draw_svg_path(d, pen):
    tokens = tokenize_d(d)
    ops, cmd, args = [], None, []
    for t in tokens:
        if t.isalpha():
            if cmd is not None: ops.append((cmd, args))
            cmd, args = t, []
        else:
            args.append(float(t))
    if cmd is not None: ops.append((cmd, args))

    cx, cy = 0.0, 0.0
    open_contour = False

    for cmd, args in ops:
        if cmd == 'M':
            if open_contour: pen.closePath()
            cx, cy = args[0], args[1]
            pen.moveTo((sx(cx), sy(cy)))
            open_contour = True
            i = 2
            while i+1 < len(args):
                cx, cy = args[i], args[i+1]
                pen.lineTo((sx(cx), sy(cy)))
                i += 2
        elif cmd == 'L':
            i = 0
            while i+1 < len(args):
                cx, cy = args[i], args[i+1]
                pen.lineTo((sx(cx), sy(cy)))
                i += 2
        elif cmd == 'C':
            i = 0
            while i+5 < len(args):
                x1,y1,x2,y2,x,y = args[i:i+6]
                pen.curveTo((sx(x1),sy(y1)),(sx(x2),sy(y2)),(sx(x),sy(y)))
                cx, cy = x, y
                i += 6
        elif cmd == 'A':
            i = 0
            while i+6 < len(args):
                rx,ry,rot,large,sweep,x2,y2 = args[i:i+7]
                for (p1x,p1y,p2x,p2y,ex,ey) in arc_beziers(cx,cy,rx,ry,rot,int(large),int(sweep),x2,y2):
                    pen.curveTo((sx(p1x),sy(p1y)),(sx(p2x),sy(p2y)),(sx(ex),sy(ey)))
                cx, cy = x2, y2
                i += 7
        elif cmd in ('Z','z'):
            pen.closePath()
            open_contour = False

    if open_contour:
        pen.closePath()


# ── font builder ────────────────────────────────────────────────────────────

def build_font(svg_path, out_path):
    tree = ET.parse(svg_path)
    root = tree.getroot()

    # Build logo charstring
    logo_pen = T2CharStringPen(width=UPM, glyphSet=None)
    for elem in root.iter():
        tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
        if tag == 'circle':
            draw_circle(float(elem.attrib['cx']), float(elem.attrib['cy']),
                        float(elem.attrib['r']), logo_pen)
        elif tag == 'path':
            d = elem.attrib.get('d', '')
            if d:
                draw_svg_path(d, logo_pen)
    logo_cs = logo_pen.getCharString()

    # .notdef — thin empty rectangle
    nd_pen = T2CharStringPen(width=600, glyphSet=None)
    nd_pen.moveTo((50, 0)); nd_pen.lineTo((550, 0))
    nd_pen.lineTo((550, 700)); nd_pen.lineTo((50, 700))
    nd_pen.closePath()
    nd_pen.moveTo((100, 50)); nd_pen.lineTo((100, 650))
    nd_pen.lineTo((500, 650)); nd_pen.lineTo((500, 50))
    nd_pen.closePath()
    notdef_cs = nd_pen.getCharString()

    fb = FontBuilder(UPM, isTTF=False)
    fb.setupGlyphOrder([".notdef", "logo"])
    fb.setupCharacterMap({0xE000: "logo"})
    fb.setupNameTable({
        "familyName": "AlinixLogo",
        "styleName": "Regular",
        "psName": "AlinixLogo-Regular",
    })
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupHorizontalMetrics({".notdef": (600, 0), "logo": (UPM, 0)})
    fb.setupPost()
    fb.setupOS2(
        sTypoAscender=800, sTypoDescender=-200, sTypoLineGap=0,
        usWinAscent=800, usWinDescent=200,
        fsType=0, fsSelection=0,
        ulUnicodeRange1=0, ulCodePageRange1=1<<0,
    )
    fb.setupCFF(
        psName="AlinixLogo-Regular",
        fontInfo={
            "version": "1.0",
            "FullName": "AlinixLogo Regular",
            "FamilyName": "AlinixLogo",
            "Weight": "Regular",
            "isFixedPitch": False,
            "UnderlinePosition": -100,
            "UnderlineThickness": 50,
        },
        charStringsDict={".notdef": notdef_cs, "logo": logo_cs},
        privateDict={"defaultWidthX": 0, "nominalWidthX": 0},
    )

    fb.font.save(out_path)
    print(f"Saved: {out_path}")


if __name__ == "__main__":
    svg = sys.argv[1] if len(sys.argv) > 1 else \
        "/home/jefferson/Desktop/projects/Alinix-Deb/sys/assets/logo.svg"
    out = sys.argv[2] if len(sys.argv) > 2 else \
        "/home/jefferson/.local/share/fonts/opentype/AlinixLogo-Regular.otf"
    build_font(svg, out)
