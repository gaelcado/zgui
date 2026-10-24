#!/usr/bin/env python3
"""Zeron's built-in themes as zgui theme files.

Reads the seeds of every variant in comet's crates/theme/src/builtins.rs
and derives the roles the way `variant()` and `AccentRoles::derive` do
(mixes, alpha washes, the contrast lifts), then writes one zgui theme JSON
per variant beside this script, on the token mapping zeron-dark.json
documents, plus kit/theme_list.luau for the workbench's picker.

    python3 themes/generate.py [path/to/builtins.rs]
"""
import json, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / "zeron/comet/crates/theme/src/builtins.rs"


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


def hex6(c):
    return "#%02x%02x%02x" % tuple(int(round(v)) for v in c)


def hexa(c, a):
    return hex6(c) + "%02x" % int(round(max(0, min(1, a)) * 255))


def lum(c):
    def lin(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

    return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])


def contrast(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


WHITE, BLACK = (255, 255, 255), (0, 0, 0)


def best_on(c):
    return WHITE if contrast(WHITE, c) >= contrast(BLACK, c) else BLACK


def ensure(c, bg, minimum):
    if contrast(c, bg) >= minimum:
        return c
    target = BLACK if contrast(BLACK, bg) >= contrast(WHITE, bg) else WHITE
    for step in range(1, 21):
        cand = mix(c, target, step / 20)
        if contrast(cand, bg) >= minimum:
            return cand
    return target


def over(top, alpha, under):
    return tuple(t * alpha + u * (1 - alpha) for t, u in zip(top, under))


def ensure_all(c, bgs, minimum, away):
    """Zeron's harden_model_foreground: `c` moved toward `away` just far
    enough to read at `minimum` on every surface in `bgs`."""
    for step in range(0, 41):
        cand = mix(c, away, step / 40)
        if min(contrast(cand, b) for b in bgs) >= minimum:
            return cand
    return away


def step_fill(fill, toward, t, label):
    """A state step: `fill` moved `t` toward `toward`, but never so far its
    label drops under 4.5:1."""
    while t > 0.005 and contrast(label, mix(fill, toward, t)) < 4.5:
        t -= 0.01
    return mix(fill, toward, max(t, 0))


def plate(color, on=None):
    """A fill that carries a label: `color` darkened (or lightened) just far
    enough that `on` reads on it at 4.5:1, keeping its hue, with hover and
    pressed steps that only move further from the label."""
    on = on or best_on(color)
    away = BLACK if on == WHITE else WHITE
    strong = color
    for step in range(1, 41):
        if contrast(on, strong) >= 4.5:
            break
        strong = mix(color, away, step / 40)
    return dict(strong=strong, on=on, hover=mix(strong, away, 0.08), pressed=mix(strong, away, 0.16))


def accent_roles(primary, dark, bg):
    primary = ensure(primary, bg, 3.0)
    on = best_on(primary)
    strong = primary if contrast(on, primary) >= 4.5 else ensure(primary, on, 4.5)
    light = mix(primary, WHITE if dark else bg, 0.28 if dark else 0.18)
    return dict(primary=primary, on=on, strong=strong, light=light)


SEED = re.compile(
    r'variant\(Seeds \{\s*id: "(?P<id>[^"]+)",\s*family_id: "(?P<family>[^"]+)",\s*name: "(?P<name>[^"]+)",\s*'
    r"appearance: Appearance::(?P<appearance>\w+),\s*treatment: SurfaceTreatment::(?P<treatment>\w+),\s*"
    r'background: "(?P<background>[^"]+)",\s*shell: "(?P<shell>[^"]+)",\s*raised: "(?P<raised>[^"]+)",\s*card: "(?P<card>[^"]+)",\s*'
    r'text: "(?P<text>[^"]+)",\s*muted: "(?P<muted>[^"]+)",\s*faint: "(?P<faint>[^"]+)",\s*accent: "(?P<accent>[^"]+)",\s*'
    r'danger: "(?P<danger>[^"]+)",\s*warning: "(?P<warning>[^"]+)",\s*success: "(?P<success>[^"]+)",\s*'
    r'terminal_background: "(?P<terminal>[^"]+)",\s*ansi: (?P<ansi>ANSI_\w+|\[[^\]]*\]),\s*syntax: \[(?P<syntax>[^\]]*)\]',
    re.S,
)
FAMILY = re.compile(r'family\(\s*"([^"]+)",\s*"([^"]+)",\s*vec!\[', re.S)


def build(seed, template):
    dark = seed["appearance"] == "Dark"
    bg, shell, raised, card = (rgb(seed[k]) for k in ("background", "shell", "raised", "card"))
    text = rgb(seed["text"])
    tone = WHITE if dark else BLACK
    # Body text reads at 4.5:1 on every surface it sits on, the strongest
    # control wash (ink 16%) included.
    surfaces = [bg, shell, raised, card, over(tone, 0.16, bg)]
    text = ensure_all(text, surfaces, 4.5, tone)
    muted = ensure(rgb(seed["muted"]), bg, 4.5)
    faint = rgb(seed["faint"])
    danger, warning, success = rgb(seed["danger"]), rgb(seed["warning"]), rgb(seed["success"])
    acc = accent_roles(rgb(seed["accent"]), dark, bg)
    solid = (235, 235, 239) if dark else (35, 35, 40)
    syntax = re.findall(r'"(#[0-9a-fA-F]{6})"', seed["syntax"])
    info = rgb(syntax[5]) if len(syntax) > 5 else acc["primary"]
    overlay = mix(card, raised, 0.34 if dark else 0.02)
    dialog = mix(card, raised, 0.18 if dark else 0.04)
    ink = lambda a: hexa(tone, a)
    t = json.loads(json.dumps(template))
    tok = t["tokens"]
    t["name"] = seed["id"]
    t["type"] = "dark" if dark else "light"
    t["extends"] = "zgui-dark" if dark else "zgui-light"
    tok["background"] = hex6(bg)
    tok["surface"] = {"sunken": hex6(rgb(seed["terminal"])), "base": hex6(shell), "raised": hex6(raised), "overlay": hex6(overlay)}
    tok["text"] = {"primary": hex6(text), "secondary": hex6(muted), "tertiary": hex6(faint), "disabled": hexa(text, 0.38)}
    tok["border"] = ink(0.10 if dark else 0.12)
    tok["border.subtle"] = ink(0.06 if dark else 0.07)
    tok["border.strong"] = ink(0.18 if dark else 0.22)
    tok["accent"] = hex6(acc["primary"])
    tok["accent.hover"] = hex6(acc["light"])
    tok["accent.text"] = hex6(acc["on"])
    tok["danger"], tok["warning"], tok["success"], tok["info"] = hex6(danger), hex6(warning), hex6(success), hex6(info)
    tok["selection"] = hexa(acc["primary"], 0.35 if dark else 0.24)
    tok["selection.item"] = hexa((235, 235, 235) if dark else (26, 26, 26), 0.11 if dark else 0.06)
    tok["hover"] = ink(0.11 if dark else 0.06)
    tok["pressed"] = hexa(acc["primary"], 0.18 if dark else 0.10)
    tok["scrollbar"] = {"thumb": hexa(text, 0.30), "thumb.active": hexa(text, 0.55), "track": "#00000000"}
    tok["glass"] = {"tint": hexa(shell, 0.80), "blur": 24}
    tok["button.bg"] = "{surface.raised}"
    # Controls hover and press within their own family: text washes, never
    # the engine's opaque defaults.
    tok["button.hover"] = "alpha({text.primary}, 0.08)"
    tok["button.pressed"] = "alpha({text.primary}, 0.12)"
    tok["input.bg"] = hexa(raised, 0.72) if dark else hex6(card)
    tok["menu.bg"] = "{surface.overlay}"
    z = tok["zeron"]
    z["card"] = hex6(card)
    z["dialog"] = hex6(dialog)
    z["input.border"] = "#bdc7d117" if dark else "#4352601a"
    z["solid"] = hex6(solid)
    z["on_solid"] = hex6(best_on(solid))
    z["solid.hover"] = hex6(step_fill(solid, bg, 0.12, best_on(solid)))
    z["solid.pressed"] = hex6(step_fill(solid, bg, 0.2, best_on(solid)))
    z["danger.muted"] = hex6(mix(danger, text, 0.28))
    # Plates: a status colour as a fill under a label, always 4.5:1 or more.
    # Danger and info carry white, as Zeron's destructive fill does.
    for name, color, on in (("danger", danger, WHITE), ("info", info, WHITE), ("warning", warning, None), ("success", success, None)):
        p = plate(color, on)
        z[name + ".strong"] = hex6(p["strong"])
        z[name + ".text"] = hex6(p["on"])
        z[name + ".hover"] = hex6(p["hover"])
        z[name + ".pressed"] = hex6(p["pressed"])
    z["warning.muted"] = hex6(mix(warning, text, 0.25))
    z["success.muted"] = hex6(mix(success, text, 0.25))
    z["accent"] = {"wash": hexa(acc["primary"], 0.22 if dark else 0.12), "selection": hexa(acc["primary"], 0.35 if dark else 0.24)}
    z["ink"] = {str(i + 1): ink(a) for i, a in enumerate((0.04, 0.06, 0.08, 0.11, 0.16, 0.22))}
    z["diff"] = {"add": hex6(success), "delete": hex6(danger), "hunk": hexa(acc["primary"], 0.08 if dark else 0.07)}
    z["cursor"] = hexa(text, 0.40 if dark else 0.55)
    z["code.wash"] = hexa(acc["primary"], 0.22 if dark else 0.12)
    z["glass"] = {"active": ink(0.11), "hover": ink(0.05)}
    t["_source"] = {"family": seed["family"], "name": seed["name"], "treatment": seed["treatment"], "from": "comet crates/theme/src/builtins.rs"}
    return t


def main():
    src = SRC.read_text()
    families = dict(FAMILY.findall(src))
    template = json.loads(re.sub(r"^\s*//.*$", "", (HERE.parent / "zeron-dark.json").read_text(), flags=re.M))
    listing = []
    for m in SEED.finditer(src):
        seed = m.groupdict()
        theme = build(seed, template)
        (HERE / f"{seed['id']}.json").write_text(json.dumps(theme, indent="\t") + "\n")
        listing.append((seed["family"], families.get(seed["family"], seed["family"]), seed["id"], seed["name"], theme["type"], seed["treatment"] == "Frosted"))
    lines = ["-- Zeron's built-in themes, generated by themes/generate.py from comet's", "-- builtins.rs: family, variant id, name, dark or light, and whether its", "-- surfaces are frosted (SurfaceTreatment; opaque unless said).", "export type Entry = {", "\tfamily: string,", "\tfamily_name: string,", "\tid: string,", "\tname: string,", "\tkind: \"dark\" | \"light\",", "\tfrosted: boolean?,", "}", "local THEMES: { Entry } = {"]
    for fam, fam_name, vid, name, kind, frosted in listing:
        flag = ", frosted = true" if frosted else ""
        lines.append(f'\t{{ family = "{fam}", family_name = "{fam_name}", id = "{vid}", name = "{name}", kind = "{kind}"{flag} }},')
    lines += ["}", "return THEMES", ""]
    (HERE.parent / "kit" / "theme_list.luau").write_text("\n".join(lines))
    print(f"{len(listing)} variants")


main()
