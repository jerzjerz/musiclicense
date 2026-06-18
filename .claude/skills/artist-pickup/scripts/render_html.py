#!/usr/bin/env python3
"""Render a ranked artist-pickup result (score.py output) as a standalone HTML dossier.

Why a separate script: presentation is a delivery concern, kept out of the core
scoring (score.py). This reads the SAME ranked JSON and emits a self-contained,
audit-friendly page — one file, no build step, fonts via CDN — so a reviewer can
eyeball every criterion, score, source, and confidence at a glance.

Input: ranked JSON (score.py stdout) via stdin or argv[1].
       {label, weights, ranked:[{rank,name,composite,tier,subscores,evidence,stored,notes,missing}]}
Output: --out PATH (default: artist-pickup.html). --lens / --date are optional headers.
"""
import json
import sys
import re
import html
import argparse

# Display order + short labels for the six pickup criteria (matches score.py keys).
CRITERIA = [
    ("streaming", "Spotify 스트리밍"),
    ("genre", "장르 적합성"),
    ("label", "인디 vs 메이저"),
    ("followers", "SNS 팔로워"),
    ("catalog", "카탈로그 + 반응"),
    ("china", "중국 활동"),
]
CONF_RE = re.compile(r"(높음|중간|낮음)")
CONF_CLASS = {"높음": "hi", "중간": "mid", "낮음": "lo"}


def confidence(evidence_text):
    """Pull the data-confidence tag (높음/중간/낮음) out of an evidence string."""
    found = CONF_RE.findall(evidence_text or "")
    return found[-1] if found else None


def esc(s):
    return html.escape(str(s)) if s is not None else ""


CSS = """
:root{
  --bg:#EDEAE2; --card:#FBFAF6; --ink:#18161B; --muted:#6E6A62; --line:#E1DCD2;
  --crimson:#CE1126; --crimson-soft:#F3D6D9;
  --hi:#2F7D58; --mid:#B4791C; --lo:#9A9590;
}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{
  margin:0; background:var(--bg); color:var(--ink);
  font-family:"Inter",system-ui,sans-serif; line-height:1.5;
  font-feature-settings:"ss01","cv05";
}
.wrap{max-width:940px; margin:0 auto; padding:40px 22px 72px}
.mono{font-family:"Space Mono","SFMono-Regular",monospace; font-variant-numeric:tabular-nums}
.display{font-family:"Archivo",sans-serif}

/* ---- header ---- */
header{border-bottom:2px solid var(--ink); padding-bottom:18px; margin-bottom:8px}
.eyebrow{font-size:12px; letter-spacing:.16em; text-transform:uppercase; color:var(--crimson); font-weight:700}
h1{font-family:"Archivo",sans-serif; font-weight:800; font-size:clamp(30px,6vw,48px);
   letter-spacing:-.02em; margin:8px 0 4px; line-height:1}
.sub{color:var(--muted); font-size:14px}
.meta{display:flex; flex-wrap:wrap; gap:6px 18px; margin-top:14px; font-size:13px; color:var(--muted)}
.meta b{color:var(--ink); font-weight:600}

/* ---- criteria legend ---- */
.legend{display:flex; flex-wrap:wrap; gap:8px; margin:22px 0 30px}
.legend .lg{display:flex; align-items:baseline; gap:7px; background:var(--card);
  border:1px solid var(--line); border-radius:999px; padding:6px 12px; font-size:13px}
.legend .w{font-family:"Space Mono",monospace; font-weight:700; color:var(--crimson); font-size:12px}

/* ---- card ---- */
.card{background:var(--card); border:1px solid var(--line); border-radius:14px;
  padding:22px 24px; margin-bottom:18px; box-shadow:0 1px 0 rgba(0,0,0,.03)}
.top{display:flex; align-items:flex-start; gap:18px}
.rank{font-family:"Space Mono",monospace; font-size:34px; font-weight:700; color:var(--crimson);
  line-height:1; min-width:46px}
.who{flex:1; min-width:0}
.name{font-family:"Archivo",sans-serif; font-weight:800; font-size:24px; letter-spacing:-.01em; line-height:1.1}
.stored{color:var(--muted); font-size:13px; margin-top:3px}
.scorebox{text-align:right}
.composite{font-family:"Space Mono",monospace; font-weight:700; font-size:34px; line-height:1}
.composite span{font-size:15px; color:var(--muted); font-weight:400}
.tier{display:inline-block; margin-top:4px; font-family:"Archivo",sans-serif; font-weight:700;
  font-size:12px; letter-spacing:.08em; padding:2px 9px; border-radius:6px; color:#fff}
.tier-S{background:var(--crimson)} .tier-A{background:var(--ink)}
.tier-B{background:#7C766B} .tier-C{background:#A8A299}

/* ---- contribution strip (signature) ---- */
.strip{display:flex; height:30px; border-radius:7px; overflow:hidden; margin:18px 0 4px;
  border:1px solid var(--line)}
.seg{position:relative; border-right:1px solid rgba(255,255,255,.6)}
.seg:last-child{border-right:0}
.seg.miss{background:repeating-linear-gradient(45deg,#EEE9E0,#EEE9E0 5px,#E3DDD2 5px,#E3DDD2 10px)}
.striplab{font-size:11px; color:var(--muted); margin-bottom:18px}

/* ---- criterion rows ---- */
.crits{margin-top:14px; border-top:1px dashed var(--line)}
.crit{display:grid; grid-template-columns:128px 42px 1fr; gap:12px; align-items:center;
  padding:11px 0; border-bottom:1px dashed var(--line)}
.crit .clabel{font-size:13px; font-weight:600}
.crit .cw{font-size:11px; color:var(--muted); font-family:"Space Mono",monospace}
.crit .cscore{font-family:"Space Mono",monospace; font-weight:700; font-size:15px; text-align:right}
.crit .cscore.na{color:var(--lo); font-weight:400; font-size:13px}
.bar{height:7px; background:#ECE7DD; border-radius:4px; overflow:hidden; margin:6px 0 7px}
.bar i{display:block; height:100%; background:var(--crimson); border-radius:4px}
.ev{font-size:12.5px; color:var(--muted); display:flex; gap:8px; align-items:flex-start}
.conf{flex:none; font-size:10.5px; font-weight:700; padding:1px 7px; border-radius:5px;
  text-transform:uppercase; letter-spacing:.04em; margin-top:1px}
.conf.hi{background:#E2F0E8; color:var(--hi)} .conf.mid{background:#F6EAD3; color:var(--mid)}
.conf.lo{background:#ECE9E3; color:var(--lo)}
.cell{min-width:0}

/* ---- notes ---- */
.notes{margin-top:14px; background:#F4EFE6; border-left:3px solid var(--crimson);
  padding:11px 14px; border-radius:0 8px 8px 0; font-size:13.5px}
.notes b{color:var(--crimson); font-weight:700; font-size:11px; letter-spacing:.08em; text-transform:uppercase;
  display:block; margin-bottom:3px}

footer{margin-top:34px; padding-top:16px; border-top:1px solid var(--line);
  font-size:12px; color:var(--muted)}
footer .warn{color:var(--mid)}

a:focus-visible,.card:focus-within{outline:2px solid var(--crimson); outline-offset:2px}
@media (max-width:640px){
  .crit{grid-template-columns:1fr 40px; }
  .crit .cell{grid-column:1 / -1}
  .scorebox{margin-left:auto}
}
@media (prefers-reduced-motion:no-preference){
  .bar i,.seg{transition:width .5s ease}
}
"""


def seg_color(score):
    # crimson with opacity tied to score so weight (width) x score (intensity) read at a glance
    op = 0.18 + 0.80 * (score / 100.0)
    return f"rgba(206,17,38,{op:.2f})"


def render(data, lens="", date=""):
    weights = data.get("weights", {})
    wsum = sum(weights.values()) or 1
    wpct = {k: 100 * v / wsum for k, v in weights.items()}
    label = data.get("label", "artist-pickup")

    out = []
    out.append("<!doctype html><html lang='ko'><head><meta charset='utf-8'>")
    out.append("<meta name='viewport' content='width=device-width,initial-scale=1'>")
    out.append(f"<title>Artist Pickup — {esc(label)}</title>")
    out.append("<link rel='preconnect' href='https://fonts.googleapis.com'>")
    out.append("<link rel='preconnect' href='https://fonts.gstatic.com' crossorigin>")
    out.append("<link href='https://fonts.googleapis.com/css2?family=Archivo:wght@600;800&"
               "family=Inter:wght@400;500;600&family=Space+Mono:wght@400;700&display=swap' rel='stylesheet'>")
    out.append(f"<style>{CSS}</style></head><body><div class='wrap'>")

    # header
    out.append("<header>")
    out.append("<div class='eyebrow'>NetEase A&amp;R · 라이선스 발굴 검수</div>")
    out.append(f"<h1>ARTIST PICKUP</h1>")
    out.append(f"<div class='sub'>{esc(label)}</div>")
    out.append("<div class='meta'>")
    if lens:
        out.append(f"<span><b>렌즈</b> {esc(lens)}</span>")
    out.append(f"<span><b>후보</b> {len(data.get('ranked', []))}명</span>")
    if date:
        out.append(f"<span><b>생성</b> {esc(date)}</span>")
    out.append("<span><b>점수</b> 6기준 가중평균 0–100 · 전부 소프트(탈락 없음)</span>")
    out.append("</div></header>")

    # criteria legend
    out.append("<div class='legend'>")
    for key, lab in CRITERIA:
        out.append(f"<span class='lg'>{esc(lab)} <span class='w'>{round(wpct.get(key,0))}%</span></span>")
    out.append("</div>")

    # cards
    for a in data.get("ranked", []):
        subs = a.get("subscores", {})
        ev = a.get("evidence", {})
        out.append("<div class='card' tabindex='0'>")
        # top
        out.append("<div class='top'>")
        out.append(f"<div class='rank mono'>{a.get('rank','')}</div>")
        out.append("<div class='who'>")
        out.append(f"<div class='name'>{esc(a.get('name'))}</div>")
        st = a.get("stored", {}) or {}
        bits = []
        if st.get("nationality"):
            bits.append(esc(st["nationality"]))
        if st.get("age") is not None:
            bits.append(f"나이 {esc(st['age'])}")
        else:
            bits.append("나이 미확인")
        out.append(f"<div class='stored'>{' · '.join(bits)}</div>")
        out.append("</div>")  # who
        tier = a.get("tier", "C")
        out.append("<div class='scorebox'>")
        out.append(f"<div class='composite mono'>{a.get('composite','')}<span>/100</span></div>")
        out.append(f"<span class='tier tier-{esc(tier)}'>{esc(tier)} TIER</span>")
        out.append("</div></div>")  # scorebox, top

        # contribution strip
        out.append("<div class='strip'>")
        for key, lab in CRITERIA:
            w = wpct.get(key, 0)
            sc = subs.get(key)
            if sc is None:
                out.append(f"<div class='seg miss' style='width:{w:.2f}%' title='{esc(lab)}: 불명'></div>")
            else:
                out.append(f"<div class='seg' style='width:{w:.2f}%;background:{seg_color(sc)}' "
                           f"title='{esc(lab)}: {sc} (비중 {round(w)}%)'></div>")
        out.append("</div>")
        out.append("<div class='striplab'>↑ 너비 = 비중 · 채도 = 점수 — 종합점수가 어디서 왔는지</div>")

        # criterion rows
        out.append("<div class='crits'>")
        for key, lab in CRITERIA:
            sc = subs.get(key)
            evtxt = ev.get(key, "")
            conf = confidence(evtxt)
            out.append("<div class='crit'>")
            out.append(f"<div><div class='clabel'>{esc(lab)}</div>"
                       f"<div class='cw'>비중 {round(wpct.get(key,0))}%</div></div>")
            if sc is None:
                out.append("<div class='cscore na'>N/A</div>")
            else:
                out.append(f"<div class='cscore mono'>{sc}</div>")
            out.append("<div class='cell'>")
            if sc is not None:
                out.append(f"<div class='bar'><i style='width:{sc}%'></i></div>")
            out.append("<div class='ev'>")
            if conf:
                out.append(f"<span class='conf {CONF_CLASS[conf]}'>{conf}</span>")
            out.append(f"<span>{esc(evtxt)}</span>")
            out.append("</div></div>")  # ev, cell
            out.append("</div>")  # crit
        out.append("</div>")  # crits

        if a.get("missing"):
            miss = ", ".join(dict(CRITERIA).get(m, m) for m in a["missing"])
            out.append(f"<div class='striplab'>데이터 불명으로 점수 제외(가중치 재정규화): {esc(miss)}</div>")

        if a.get("notes"):
            out.append(f"<div class='notes'><b>맥락 코멘트</b>{esc(a['notes'])}</div>")
        out.append("</div>")  # card

    # footer
    out.append("<footer>")
    out.append("<div class='warn'>⚠ 신뢰도 칩(높음/중간/낮음)은 데이터 출처의 확실성. "
               "스트리밍 절대수치 등 '중간/낮음' 항목은 검수·재확인 권장.</div>")
    out.append("<div style='margin-top:6px'>점수는 근거와 함께만 사용 — 모든 항목에 출처·신뢰도 표기. "
               "music-license · artist-pickup</div>")
    out.append("</footer>")
    out.append("</div></body></html>")
    return "".join(out)


def main():
    ap = argparse.ArgumentParser(description="Render ranked pickup JSON as HTML.")
    ap.add_argument("input", nargs="?", help="Ranked JSON path (default: stdin)")
    ap.add_argument("--out", default="artist-pickup.html")
    ap.add_argument("--lens", default="")
    ap.add_argument("--date", default="")
    args = ap.parse_args()
    raw = open(args.input).read() if args.input else sys.stdin.read()
    data = json.loads(raw)
    htmlout = render(data, lens=args.lens, date=args.date)
    with open(args.out, "w") as f:
        f.write(htmlout)
    print(f"wrote {args.out} ({len(htmlout)} bytes)")


if __name__ == "__main__":
    main()
