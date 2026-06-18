# music-license

NetEase Cloud Music을 위한 **아티스트 발굴·평가·라이선스 인텔리전스 도구**.
공개 스트리밍/소셜 + 웹 데이터로 아티스트를 발굴하고, 6개 기준으로 점수화·랭킹해
*라이선스할 만한 후보를 근거와 함께* 추려낸다.

> 방향·철학은 [CLAUDE.md](./CLAUDE.md)(작업 규약·톤앤매너)와 [CONTEXT.md](./CONTEXT.md)(비전·기준·결정 로그)가 정본이다.
> 작업을 이어가려면 **CONTEXT.md 맨 아래 「현재 상태 & 다음 세션 이어가기」** 부터 읽으면 된다.

## 구조
```
music-license/
├── CLAUDE.md      # HOW — 작업 원칙·톤앤매너·세션 종료 루틴
├── CONTEXT.md     # WHAT/WHY — 비전·픽업 기준(정본)·결정 로그·현재 상태
├── data/          # 발굴·채점 입력 데이터 (영속)
│   └── western-rising-2026.json
├── reports/       # 산출물 (마크다운·HTML 리포트)
└── .claude/skills/artist-pickup/   # 픽업 스킬
    ├── SKILL.md                    # 워크플로 · 6기준 루브릭 · 데이터 획득법
    └── scripts/
        ├── spotify.py              # Spotify fetch (stdlib only)
        ├── score.py                # 가중·랭킹·마크다운 렌더 (코어)
        └── render_html.py          # scored JSON → HTML 검수 페이지 (딜리버리)
```

## 픽업 기준 (6축, 전부 소프트 가중)
| 기준 | 비중 |
|------|:---:|
| Spotify 스트리밍·지표 | 21% |
| 장르 적합성 (힙합/R&B/POP) | 21% |
| 인디 vs 메이저 (인디 선호) | 21% |
| SNS 팔로워 (IG/YT) | 14% |
| 카탈로그 규모 + 시장 반응 | 14% |
| 중국 활동 가능성 | 7% |

나이는 점수가 아닌 *저장·표시 항목*(타겟 오디언스용). 상세 정의는 CONTEXT.md 「아티스트 픽업 기준」 참고.

## 빠른 시작 (재현 파이프라인)
필요: Python 3 (표준 라이브러리만). Spotify 자동 fetch를 쓰려면 `SPOTIFY_CLIENT_ID`/`SPOTIFY_CLIENT_SECRET` 환경변수(없어도 동작).

```bash
# 1) 채점 데이터(data/<label>.json)를 점수화·랭킹 → 마크다운 리포트
python3 .claude/skills/artist-pickup/scripts/score.py data/western-rising-2026.json \
  --report reports/artist-pickup-western-rising-2026.md

# 2) 같은 데이터를 HTML 검수 페이지로 렌더
python3 .claude/skills/artist-pickup/scripts/score.py data/western-rising-2026.json \
  | python3 .claude/skills/artist-pickup/scripts/render_html.py \
      --out reports/artist-pickup-western-rising-2026.html \
      --lens "서양권 라이징 인디" --date 2026-06-18
```

`data/<label>.json` 스키마와 사용법은 `.claude/skills/artist-pickup/SKILL.md`에 있다.

## 상태
초기 단계. 픽업 스킬 1개 + 첫 발굴 사이클(서양권 5인) 완료. 다음 작업(HTML/데이터 포맷/레이아웃 개선 등)은 CONTEXT.md 「현재 상태 & 다음 세션 이어가기」 참고.
