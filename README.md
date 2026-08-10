# music-license

NetEase Cloud Music A&R을 위한 **아티스트 발굴·평가·라이선스 작업실**.
공개 스트리밍/소셜 데이터로 아티스트를 발굴해 4개 기준으로 점수화·랭킹하고, 딜 제안서를 조판하고, 사내 도구(POPO)·중국어 소통까지 함께 다룬다.

---

## 처음 왔다면 — 이 순서로 읽으면 된다

1. **[CONTEXT.md](./CONTEXT.md)** — WHAT/WHY. 비전·픽업 기준(정본)·결정 로그.
   → **맨 아래 「현재 상태 & 다음 세션 이어가기」부터 보면 바로 이어갈 수 있다.**
2. **[CLAUDE.md](./CLAUDE.md)** — HOW. 작업 원칙·톤앤매너·설계 협의 규약·세션 종료 루틴.
3. 그다음 필요한 것만: `docs/`의 주제별 기준 문서.

Claude Code로 이 폴더를 열면 위 두 문서를 먼저 읽도록 규약에 박혀 있다.

---

## 구조

```
music-license/
├── CLAUDE.md                    # HOW — 작업 원칙 · grilling 협의 규약 · 세션 종료 루틴
├── CONTEXT.md                   # WHAT/WHY — 비전 · 픽업 기준(정본) · 결정 로그 #001~
│
├── docs/                        # 주제별 기준 문서 (정본)
│   ├── deal-proposal-context.md        # 딜 *내용* 기준 — 확정 딜 구조 · 용어 정책
│   ├── deal-proposal-design-system.md  # 딜 제안서 *디자인/언어* 토큰
│   ├── popo-automation-context.md      # 사내 메신저 网易POPO 자동화 — 도메인 지형 · 봇 프로토콜 · 제약
│   └── cn-assistant-spec.md            # 중국어 소통 보조 — 5단 출력 포맷 · 한자음 매핑
│
├── data/                        # 입력 데이터 (영속 — 재현에 필요)
│   ├── western-rising-2026.json        # artist-pickup 채점 입력
│   └── tzuyu-input.json                # deal-proposal 딜 스펙
│
├── reports/                     # 산출물
│   ├── artist-pickup-*.md / .html
│   └── deal-proposal-tzuyu.docx
│
└── .claude/skills/              # Claude Code 스킬
    ├── artist-pickup/           # 아티스트 후보 점수화·랭킹 (코어)
    ├── deal-proposal/           # 딜 제안서 JSON → docx 조판
    ├── grilling/                # 설계 협의 — 한 번에 한 질문씩 결정 트리 내려가기
    └── insane-search/           # 차단 사이트 우회 수집
```

---

## 스킬 4개

| 스킬 | 언제 부르나 | 산출물 |
|---|---|---|
| **artist-pickup** | "이 중에 누가 좋아", "라이선스 후보 추려줘", 아티스트 랭킹·비교·평가 | 랭킹표 + 스코어카드 + `reports/*.md` / `*.html` |
| **deal-proposal** | "딜 제안서 만들어줘", 오퍼레터·텀시트 작성·수정 | `reports/*.docx` (프리미엄 에디토리얼 조판) |
| **grilling** | 설계·계획 논의. **Claude가 안 불러도 알아서 켠다** | 한 번에 한 질문씩 합의 → 그 자리에서 레포에 기록 |
| **insane-search** | 웹 접근이 402/403으로 막힐 때 (X·Reddit·네이버·깃헙 등) | 우회 fetch 결과 |

---

## 픽업 기준 — 4점수축 + 2비점수 의견

> 2026-06-22 개편(결정 #006). 예전 6축은 폐기됐다. 정본은 항상 [CONTEXT.md](./CONTEXT.md) 「아티스트 픽업 기준」.

| # | 점수 기준 | 비중 |
|---|---|:---:|
| 1 | 스트리밍 (Spotify + 주요 글로벌 플랫폼) | **30%** |
| 2 | 장르 (힙합·R&B·POP 우선) | **30%** |
| 3 | SNS 팔로워 (IG 중심, 50만↑ 앵커) | **20%** |
| 4 | 카탈로그 규모 + 시장 반응 | **20%** |

**비점수 의견 2개** (한 줄 코멘트로만 표기, 점수 미반영): 인디 vs 메이저 · 국적/중국 활동 가능성.
나이는 점수가 아닌 *저장·표시 항목*(타겟 오디언스 산정용).

**타깃 기본값 = 서양권 라이징 인디** — 중화권은 이미 중국 시장을 섭렵했으므로, 화이트스페이스는 *서양 힙합/R&B/POP을 중국에 들여오는 것*이다. (결정 #003)

---

## 빠른 시작

### 1. artist-pickup — 점수화 파이프라인
필요: **Python 3만** (표준 라이브러리 전용, 설치할 것 없음).
Spotify 자동 fetch를 쓰려면 `SPOTIFY_CLIENT_ID` / `SPOTIFY_CLIENT_SECRET` 환경변수. 없어도 동작한다.

```bash
python3 .claude/skills/artist-pickup/scripts/score.py data/western-rising-2026.json --report reports/artist-pickup-western-rising-2026.md
```

```bash
python3 .claude/skills/artist-pickup/scripts/score.py data/western-rising-2026.json | python3 .claude/skills/artist-pickup/scripts/render_html.py --out reports/artist-pickup-western-rising-2026.html --lens "서양권 라이징 인디" --date 2026-06-18
```

`data/<label>.json` 스키마는 `.claude/skills/artist-pickup/SKILL.md` 참고.

### 2. deal-proposal — docx 조판
필요: **Node.js**. 최초 1회 의존성 설치가 필요하다.

```bash
npm install --prefix .claude/skills/deal-proposal/scripts
```

```bash
node .claude/skills/deal-proposal/scripts/build_proposal.js data/tzuyu-input.json --out reports/deal-proposal-tzuyu.docx
```

> 조판을 바꿔야 하면 **`docs/deal-proposal-design-system.md`를 먼저 고치고** 그다음 `build_proposal.js`의 토큰 상수를 맞춘다. 임의 손조판 금지.

---

## 규약 요약 (전문은 CLAUDE.md)

- **코어는 안정, 표현은 스킬.** 점수화 로직과 출력 형식을 섞지 않는다.
- **모든 점수엔 근거를.** 설명 못 하는 점수는 쓰지 않는다.
- **작게 시작해 점진 확장.** 과설계 금지(YAGNI).
- **방향이 바뀌면 CONTEXT.md 결정 로그에 날짜와 함께 남긴다.**
- **설계·계획 낌새가 있으면 `grilling`부터** — 한 번에 한 질문, 질문마다 추천 답, 사실은 직접 찾고 결정만 사람에게, 합의 전 실행 금지.
- 비밀키·토큰은 절대 커밋하지 않는다 (`.env`만).

---

## 상태

CONTEXT.md 결정 로그 **#001~#009**까지 진행. 스킬 4개 · 기준 문서 4종 · 발굴 1사이클 · 딜 제안서 벤치마크 1건 완료.
다음 작업은 **[CONTEXT.md 「현재 상태 & 다음 세션 이어가기」](./CONTEXT.md)** 를 보면 된다.
