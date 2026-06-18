#!/usr/bin/env python3
"""Aggregate per-artist sub-scores into a weighted composite, rank, and render a report.

Why a script: the math (weighting, renormalization when a criterion is missing,
ranking, tiering) must be deterministic and identical across every run. Judgment
— assigning each 0-100 sub-score with evidence — stays with the model. This script
only does the arithmetic and the rendering so reports never drift.

Input: a JSON object (file path as argv[1], or stdin) shaped like:

{
  "label": "kpop-rnb-shortlist",            # optional, used in the report filename/title
  "weights": {                               # optional; defaults below
    "streaming": 0.21, "genre": 0.21, "label": 0.21,
    "followers": 0.14, "catalog": 0.14, "china": 0.07
  },
  "artists": [
    {
      "name": "Artist Name",
      "subscores": {                         # 0-100 each; omit or null = "unknown" (criterion dropped, weights renormalized)
        "streaming": 85, "genre": 90, "label": 80,
        "followers": 70, "catalog": 60, "china": 50
      },
      "stored": {"age": 27, "nationality": "USA"},   # optional; age is stored/displayed, never scored
      "evidence": {"streaming": "Spotify popularity 68; ~5.4M monthly listeners (Chartmetric, med confidence)"},
      "notes": "optional one-liner for the context comment"
    }
  ]
}

Output: ranked JSON to stdout. Pass --report PATH to also write a Markdown report.
"""
import json
import sys
import argparse

DEFAULT_WEIGHTS = {
    "streaming": 0.21,
    "genre": 0.21,
    "label": 0.21,
    "followers": 0.14,
    "catalog": 0.14,
    "china": 0.07,
}

CRITERIA_LABELS = {
    "streaming": "Spotify 스트리밍·지표",
    "genre": "장르 적합성 (힙합/R&B/POP)",
    "label": "인디 vs 메이저",
    "followers": "SNS 팔로워 (IG/YT)",
    "catalog": "카탈로그 규모 + 반응",
    "china": "중국 활동 가능성",
}

# Composite (0-100) -> tier. Thresholds are deliberately simple and explainable.
TIERS = [(85, "S"), (70, "A"), (55, "B"), (0, "C")]


def tier_for(score):
    for threshold, name in TIERS:
        if score >= threshold:
            return name
    return "C"


def composite_for(subscores, weights):
    """Weighted average over the criteria that actually have a score.

    If a criterion is unknown (missing/null), we drop it and renormalize the
    remaining weights so a missing data point neither helps nor unfairly hurts —
    it just doesn't vote. Returns (composite, used_criteria, missing_criteria).
    """
    used, missing = {}, []
    for crit in weights:
        val = subscores.get(crit)
        if val is None:
            missing.append(crit)
        else:
            used[crit] = float(val)
    total_w = sum(weights[c] for c in used)
    if total_w == 0:
        return 0.0, used, missing
    composite = sum(used[c] * weights[c] for c in used) / total_w
    return round(composite, 1), used, missing


def rank(data):
    weights = data.get("weights") or DEFAULT_WEIGHTS
    # Normalize weights so they sum to 1 even if the caller passed raw tiers (e.g. 3/2/1).
    wsum = sum(weights.values())
    weights = {k: v / wsum for k, v in weights.items()} if wsum else DEFAULT_WEIGHTS

    ranked = []
    for art in data.get("artists", []):
        subs = art.get("subscores") or {}
        composite, used, missing = composite_for(subs, weights)
        ranked.append({
            "name": art.get("name", "(unnamed)"),
            "composite": composite,
            "tier": tier_for(composite),
            "subscores": subs,
            "missing": missing,
            "stored": art.get("stored") or {},
            "evidence": art.get("evidence") or {},
            "notes": art.get("notes", ""),
        })
    ranked.sort(key=lambda a: a["composite"], reverse=True)
    for i, a in enumerate(ranked, 1):
        a["rank"] = i
    return {"label": data.get("label", ""), "weights": weights, "ranked": ranked}


def render_markdown(result):
    label = result.get("label") or "artist-pickup"
    lines = [f"# 아티스트 픽업 결과 — {label}", ""]

    # Weights line so the report is self-explaining.
    wpct = ", ".join(
        f"{CRITERIA_LABELS.get(k, k)} {round(v * 100)}%"
        for k, v in result["weights"].items()
    )
    lines += [f"_비중: {wpct}_", "", "## 랭킹", "",
              "| 순위 | 아티스트 | 종합점수 | 등급 |",
              "|:---:|---|:---:|:---:|"]
    for a in result["ranked"]:
        lines.append(f"| {a['rank']} | {a['name']} | {a['composite']} | {a['tier']} |")
    lines += ["", "## 스코어카드", ""]

    for a in result["ranked"]:
        lines.append(f"### {a['rank']}. {a['name']} — {a['composite']} ({a['tier']})")
        if a["notes"]:
            lines.append(f"> {a['notes']}")
        lines.append("")
        lines.append("| 기준 | 점수 | 근거 |")
        lines.append("|---|:---:|---|")
        for crit in DEFAULT_WEIGHTS:
            score = a["subscores"].get(crit)
            score_txt = "불명" if score is None else str(score)
            ev = a["evidence"].get(crit, "")
            lines.append(f"| {CRITERIA_LABELS[crit]} | {score_txt} | {ev} |")
        stored = a["stored"]
        if stored:
            bits = []
            if stored.get("age") is not None:
                bits.append(f"나이 {stored['age']} (타겟 오디언스 메모)")
            if stored.get("nationality"):
                bits.append(f"국적 {stored['nationality']}")
            for k, v in stored.items():
                if k not in ("age", "nationality"):
                    bits.append(f"{k} {v}")
            if bits:
                lines.append(f"| _저장 항목_ | — | {', '.join(bits)} |")
        if a["missing"]:
            miss = ", ".join(CRITERIA_LABELS.get(m, m) for m in a["missing"])
            lines.append("")
            lines.append(f"_데이터 불명으로 점수 제외(가중치 재정규화): {miss}_")
        lines.append("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description="Rank artists by weighted sub-scores.")
    ap.add_argument("input", nargs="?", help="Path to input JSON (default: stdin)")
    ap.add_argument("--report", help="Write a Markdown report to this path")
    args = ap.parse_args()

    raw = open(args.input).read() if args.input else sys.stdin.read()
    data = json.loads(raw)
    result = rank(data)

    if args.report:
        with open(args.report, "w") as f:
            f.write(render_markdown(result))
        result["report_path"] = args.report

    json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
