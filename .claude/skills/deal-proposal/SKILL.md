---
name: deal-proposal
description: >-
  아티스트에게 전달할 딜 제안서(독점 EP/싱글/앨범 파트너십 등)를 비전문가도 이해할 수 있는
  프리미엄 에디토리얼 docx로 만든다. 사용자가 "딜 제안서/프로포절 만들어줘", "이 조건으로
  아티스트한테 보낼 제안서", "deal proposal", "오퍼레터/텀시트 문서화", "이 제안서 다듬어줘"
  처럼 아티스트 대상 계약/오퍼 문서를 작성·수정·조판해달라고 할 때 사용한다. 기존 제안서(docx 등)를
  분석·정정해 다시 조판하는 경우에도 사용한다. 후보 점수화·랭킹(누구를 뽑을지)은 이 스킬이 아니다.
---

# Deal Proposal — 아티스트 딜 제안서 조판

아티스트(및 그 부모님·매니지먼트 비법률 담당자)가 읽을 **딜 제안서**를, 합의된 딜 내용과 디자인 시스템에 맞춰 **docx**로 만든다. 의사결정자가 읽으므로 **결론 먼저, 근거 뒤**.

## 시작 전 항상 읽을 두 문서 (필수)
작업을 시작하기 전에 **반드시** 아래 두 파일을 읽고 그 내용을 기준으로 삼는다. 이 스킬은 이 두 문서의 **실행기**일 뿐이다.

1. **[docs/deal-proposal-context.md](../../../docs/deal-proposal-context.md)** — 딜 *내용*의 기준. 확정된 딜 구조·결정 로그·전문 용어 정책·열린 질문. **여기서 정해진 값과 어긋나는 제안서를 만들지 않는다.**
2. **[docs/deal-proposal-design-system.md](../../../docs/deal-proposal-design-system.md)** — *디자인·언어*의 기준. 컬러/타이포 토큰·컴포넌트·보이스 규칙·출력 형식(docx).

> 두 문서가 갱신되면 이 스킬도 그 갱신을 따른다. 토큰·정책을 이 SKILL.md나 스크립트에 임의로 덮어쓰지 않는다 — **문서를 먼저 고치고**, 그 다음 반영한다.

## 핵심 원칙 (context §1 / design §5)
- **결론 먼저**: 모든 섹션은 요약 콜아웃으로 연다.
- **쉬운 문장, 정확한 용어**: MG·sync·perpetual·recoupable·advance 등 **정확한 전문 용어는 그대로 쓴다.** 억지로 풀어쓰거나 빼서 부정확해지지 않는다 — 상세 설명은 대면 미팅에서 한다는 전제.
- **숫자 정합성이 신뢰**: 문서 안에서 금액·퍼센트·기간이 서로 어긋나면 안 된다. 발송 전 체크리스트(아래)를 반드시 돈다.
- **단정 못 할 건 단정하지 않는다.** 미확정 값은 `[ARTIST]` 같은 명시적 플레이스홀더로 둔다.

## 워크플로

### 1. 입력·맥락 확보
- 두 기준 문서를 읽는다.
- 이 딜의 값(아티스트명, 선급금/MG 금액, 제작비, 분배율 표, 독점기간, 포함/제외 섹션 등)을 사용자 입력·기존 제안서·context.md에서 모은다.
- **미확정 값은 추측하지 않는다.** 플레이스홀더(`[ARTIST]`)나 context.md의 제안값을 쓰고, 무엇이 플레이스홀더인지 사용자에게 알린다.
- 기존 제안서를 다듬는 경우: 먼저 원본을 추출(`unzip`→`word/document.xml`, 또는 pandoc/extract)해 읽고, context.md의 결정과 대조해 **정정할 점을 짚는다.**

### 2. 딜 스펙(JSON) 구성
제안서를 `scripts/build_proposal.js`가 먹는 **JSON 스펙**으로 표현한다. 스키마는 아래 "JSON 스펙" 참조. 섹션은 블록(`blocks`)의 배열이고, 블록 종류로 조판이 결정된다. **포함하지 않을 섹션·블록은 그냥 넣지 않는다** (예: MV·브랜드딜은 context 결정대로 기본 제외).

예시 스펙(= **기본 양식 / 벤치마크**): `examples/sample-deal.json` — 새 딜은 이걸 복제해 값만 바꾼다. 이 템플릿은 승인된 벤치마크 제안서(Tzuyu, 2026-06-26)의 구조·섹션 구성·문구를 그대로 따른다.

> **벤치마크 기준 문서**: `reference/deal-proposal-benchmark-tzuyu-2026-06-26.docx` — 앞으로 모든 아티스트 피칭 자료는 이 문서를 시각·구조 기준으로 벤치마킹한다. 재현용 입력 스펙은 `data/tzuyu-input.json`. 7섹션 골격(01 Production/후크 인물 → 02 Marketing & Promotion → 03 Deal Overview → 04 Financial Structure(A/B) → 05 Revenue Share(op-cost 후 분배) → 06 Key Terms → 07 Next Steps)을 기본 흐름으로 삼는다.

### 3. 렌더 (스크립트)
```bash
# 최초 1회: 의존성 설치
npm install --prefix .claude/skills/deal-proposal/scripts

# 렌더
node .claude/skills/deal-proposal/scripts/build_proposal.js <input.json> --out reports/deal-proposal-<label>.docx
```
디자인 토큰(컬러·폰트·여백·컴포넌트)은 **스크립트에 내장**돼 있다 = 디자인 시스템의 구현체. 조판을 손으로 바꾸지 말고 스펙(데이터)만 바꾼다. 토큰 자체를 바꿔야 하면 design-system.md를 먼저 고치고 스크립트의 토큰 상수를 그에 맞춘다.

### 4. 발송 전 정합성 체크 (필수 — context §6 체크리스트)
렌더 후 아래를 **반드시** 확인한다. 하나라도 걸리면 고치고 다시 렌더한다:
1. **숫자 정합성** — 같은 금액/퍼센트/기간이 섹션마다 동일한가? (제작비·선급금·MG·분배율·독점기간이 서로 안 맞으면 즉시 수정)
2. **플레이스홀더 잔존** — `[ARTIST]`, `X years` 같은 미입력 값이 의도치 않게 남지 않았는가? 남았다면 사용자에게 명시.
3. **전문 용어 정확성** — 용어를 정확히 썼는가(풀이는 강제 아님). 정확성을 해치는 의역이 없는가.
4. **보장 바닥/리스크 문구** — Option A는 "환수 안 됨(advance never repaid)"으로, "아티스트가 위험 부담"처럼 오해되게 쓰지 않았는가. (context의 정정 사항)
5. **준거법 존재** — 준거법·분쟁해결 한 줄이 들어갔는가.
6. **제외 항목** — context에서 제외하기로 한 섹션(MV·브랜드딜 등)이 실수로 들어가지 않았는가.

### 5. 시각 검증 & 전달
- 가능하면 렌더 결과를 눈으로 확인한다: `qlmanage -t -s 1400 -o <dir> <docx>` (표지 미리보기) 또는 LibreOffice가 있으면 PDF로 변환해 전체 페이지 확인.
- 산출물은 `reports/`에 저장한다. 채팅에는 무엇을 만들었는지·플레이스홀더가 뭔지·체크리스트 결과를 한 줄씩 보고한다.

## JSON 스펙

최상위:
```jsonc
{
  "out": "reports/deal-proposal-<label>.docx",   // 기본 출력 경로(‑‑out로 덮어쓰기 가능)
  "meta": {
    "confidentialLabel": "Strictly Private & Confidential",
    "brandLabel": "NetEase Cloud Music",          // 중립 프리미엄 — 워드마크 한 줄로만
    "titleLines": ["Exclusive Solo EP", "Partnership Proposal"],
    "footer": "Strictly Private & Confidential",
    "info": [["Prepared For","[ARTIST] & Representative(s)"], ["Date","June 2026"]]
  },
  "sections": [ /* 아래 섹션 객체들 */ ],
  "footerNote": "지시문/면책 한 줄(선택)"
}
```

섹션:
```jsonc
{
  "num": "01",                     // 섹션 번호(액센트색). 비우면 번호 없음
  "title": "Production Partnership — Amy Allen",
  "lead": "이 섹션 한 줄 리드(이탤릭).",   // 선택 — '결론 먼저'
  "pageBreakBefore": true,         // 이 섹션을 새 페이지에서 시작
  "blocks": [ /* 아래 블록들 */ ]
}
```

블록(`kind`별):
| kind | 필드 | 용도 |
|---|---|---|
| `callout` | `lines: []` | 패널+좌측 액센트바 요약 박스(결론 먼저) |
| `h2` | `text` | 소제목 |
| `para` | `text` | 본문 산문(세리프) |
| `lead` | `text` | 이탤릭 리드(섹션 lead와 동일 스타일) |
| `note` | `text` | 작은 이탤릭 캡션(보조 설명) |
| `infoTable` | `rows: [[k,v]]`, `labelW?` | 라벨/값 2열 표(Deal Overview·Key Terms) |
| `dataTable` | `headers: []`, `colW: []`, `rows: [{cells:[]} \| {band:"China"}]` | 데이터 표. `band` 행은 구간 밴드(중국/글로벌 등) |
| `optionCards` | `left/right: {label, figure, figureSub, bullets:[]}` | Option A/B 비교 카드(Key Figure 강조) |
| `checklist` | `items: []` | ✓ 체크리스트(보장 사항) |
| `spacer` | `h?` | 수직 여백 |

규칙:
- `dataTable`의 `colW` 합 = 9180(본문 폭).
- 금액·퍼센트는 셀에서 자동 우측 정렬(첫 컬럼만 좌측).
- 스마트 따옴표(`“ ” ’`)를 쓴다(평직선 따옴표 금지).

## 자주 하는 실수
- **두 기준 문서를 안 읽고 시작** → 금지. 토큰·딜 값이 어긋난다.
- **조판을 손으로 바꿈** → 스펙(데이터)만 바꾼다. 디자인은 스크립트=시스템.
- **플레이스홀더를 그럴듯한 값으로 메움** → 미확정은 플레이스홀더로 두고 사용자에게 알린다.
- **`colW` 합이 9180이 아님** → 표가 깨진다.
- **제외 섹션(MV·브랜드딜)을 습관적으로 넣음** → context 결정 확인.
