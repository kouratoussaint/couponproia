"""Génère le logo Coupon Pro IA en SVG (pictogramme + icône d'application).

Concept : un ballon de football dont la moitié droite se prolonge en circuits
électroniques (réseau neuronal), avec un arc vert d'analyse. Formes simples pour
rester lisible à 48 px.

Usage : python3 scripts/brand/generate_logo.py <dossier_sortie>
"""
import math
import sys
from pathlib import Path

GREEN = "#00D084"
DARK = "#071B1B"
WHITE = "#FFFFFF"


def pentagon(cx, cy, r, rot_deg):
    pts = []
    for k in range(5):
        a = math.radians(rot_deg + k * 72)
        pts.append(f"{cx + r * math.cos(a):.1f},{cy + r * math.sin(a):.1f}")
    return " ".join(pts)


def mark(cx=230, cy=262, r=124):
    """Éléments du pictogramme, centrés sur (cx, cy)."""
    parts = []
    # Arc d'analyse (côté gauche, en vert)
    a0, a1 = math.radians(110), math.radians(250)
    rr = r + 26
    x0, y0 = cx + rr * math.cos(a0), cy + rr * math.sin(a0)
    x1, y1 = cx + rr * math.cos(a1), cy + rr * math.sin(a1)
    parts.append(
        f'<path d="M{x0:.1f} {y0:.1f} A{rr} {rr} 0 0 1 {x1:.1f} {y1:.1f}" '
        f'fill="none" stroke="{GREEN}" stroke-width="14" stroke-linecap="round"/>'
    )
    # Ballon
    parts.append(f'<defs><clipPath id="ball"><circle cx="{cx}" cy="{cy}" r="{r}"/></clipPath></defs>')
    parts.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{WHITE}"/>')
    g = [f'<g clip-path="url(#ball)">']
    pr = r * 0.34
    g.append(f'<polygon points="{pentagon(cx, cy, pr, -90)}" fill="{DARK}"/>')
    for k in range(5):
        ang = -90 + k * 72
        a = math.radians(ang)
        vx, vy = cx + pr * math.cos(a), cy + pr * math.sin(a)
        ex, ey = cx + r * math.cos(a), cy + r * math.sin(a)
        g.append(
            f'<line x1="{vx:.1f}" y1="{vy:.1f}" x2="{ex:.1f}" y2="{ey:.1f}" '
            f'stroke="{DARK}" stroke-width="7"/>'
        )
        b = math.radians(ang + 36)
        px, py = cx + (r * 1.02) * math.cos(b), cy + (r * 1.02) * math.sin(b)
        g.append(f'<polygon points="{pentagon(px, py, r * 0.27, ang + 36 + 180)}" fill="{DARK}"/>')
    g.append("</g>")
    parts.extend(g)
    parts.append(f'<circle cx="{cx}" cy="{cy}" r="{r - 5}" fill="none" stroke="{WHITE}" stroke-width="10"/>')
    # Circuits (côté droit) : trois pistes qui sortent du ballon vers des nœuds
    traces = [
        (-38, [(48, 0), (34, -34)], "n1"),
        (-4, [(70, 0)], "n2"),
        (30, [(46, 0), (34, 34)], "n3"),
    ]
    for ang, segs, _ in traces:
        a = math.radians(ang)
        x, y = cx + (r + 4) * math.cos(a), cy + (r + 4) * math.sin(a)
        d = f"M{x:.1f} {y:.1f}"
        for dx, dy in segs:
            x, y = x + dx, y + dy
            d += f" L{x:.1f} {y:.1f}"
        parts.append(
            f'<path d="{d}" fill="none" stroke="{GREEN}" stroke-width="12" '
            f'stroke-linecap="round" stroke-linejoin="round"/>'
        )
        parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="15" fill="{GREEN}"/>')
        parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="6" fill="{DARK}"/>')
    return "\n  ".join(parts)


def svg(content, background=None, size=512, view=(0, 0, 512, 512)):
    bg = ""
    if background:
        bg = f'<rect width="512" height="512" rx="112" fill="{background}"/>\n  '
    vb = " ".join(str(v) for v in view)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="{vb}">\n  '
        f"{bg}{content}\n</svg>\n"
    )


def main(out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    m = mark()
    # Pictogramme seul, fond transparent, cadré serré (utilisé dans l'app)
    (out / "logo_mark.svg").write_text(svg(m, view=(64, 92, 384, 340)))
    # Icône complète (fond sombre arrondi)
    (out / "app_icon.svg").write_text(svg(m, background=DARK))
    # Avant-plan d'icône adaptative Android : contenu dans la zone sûre (66 %)
    fg = f'<g transform="translate(256 256) scale(0.62) translate(-256 -256)">\n  {m}\n  </g>'
    (out / "app_icon_foreground.svg").write_text(svg(fg))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "app/assets/brand")
