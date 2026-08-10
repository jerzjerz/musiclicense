# POPO 자동화 컨텍스트 (网易POPO)

> **무엇**: 사내 메신저 网易POPO를 Claude 자동화에 붙일 수 있는지, 어떻게 붙이는지의 기준 문서.
> **작성**: 2026-08-10 (1차 조사). 공식 소스 우선 + 공개 실사용 코드로 교차검증.
> **신뢰도 표기**: `[공식]` 네이즈 소유 도메인/응답으로 직접 확인 · `[교차]` 제3자 실사용 코드에서 확인(공식 문서 미열람) · `[추정]` 미검증.

---

## 결론 먼저

**된다. 공식 OpenAPI가 있고, 외부 인터넷에서 도달 가능하며, 발신·수신 양방향이 가능하다.**
단 **① 사내 corp SSO 계정 ② 개방플랫폼에서 봇/앱 등록·권한 심사** 두 관문을 통과해야 한다. 그 전까지 Claude가 POPO에 접근할 방법은 없다.

| 하고 싶은 것 | 가능? | 난이도 | 관문 |
|---|---|---|---|
| POPO 그룹에 알림 **보내기** | ✅ | 매우 낮음 | 그룹에서 웹훅 URL 발급만 |
| 특정 사람/그룹에 **보내기** | ✅ | 중간 | 앱 등록 + appKey/Secret |
| POPO 메시지 **받기**(봇 대화) | ✅ | 중간 | 앱 등록 + 이벤트 구독 설정 |
| 사내 문서·다차원표·캘린더·결재 조작 | ✅ | 중~높음 | 앱 등록 + API별 권한 신청 |
| 데스크톱 앱 UI 조작(반자동화) | △ | — | 기술적으론 가능, **사내 정책상 비권장** |

---

## 1. 도메인 지형 — 뭐가 안이고 뭐가 밖인가

| 호스트 | 실체 | 외부 접근 | 근거 |
|---|---|---|---|
| `popo.163.com` | POPO 본체(사내망 전용) | ❌ **불가** | `[공식]` Google·Cloudflare DoH 모두 **`10.82.112.24`**(사설 IP) 반환. 권威 DNS가 공개적으로 사설 IP를 응답 = 사내망에서만 붙는 설계. HTTPS 타임아웃 확인. |
| `popo.netease.com` | 공개 제품 소개 페이지 | ✅ 200 | `[공식]` AWS Global Accelerator (`15.197.253.204`) |
| **`open.popo.netease.com`** | **POPO 개방플랫폼(콘솔+문서+OpenAPI)** | ✅ 200 | `[공식]` 소개 페이지에서 링크. API는 무인증 호출 시 정상 에러코드 응답 |
| `nws.popo.netease.com:11012` | 봇 **롱커넥션 STOMP 게이트웨이** | ✅ TCP OPEN | `[공식]` DNS 공인 IP + TCP 접속 성공 |
| `docs.popo.netease.com` | POPO 云文档(灵犀) | ✅ 200(로그인 필요) | `[공식]` |
| `login.netease.com` | 网易内部认证系统 (corp SSO) | ✅ | `[공식]` 개방플랫폼 접속 시 리다이렉트 |

> **핵심 함의**: 자동화의 접점은 `popo.163.com`(사내망)이 **아니라** `open.popo.netease.com`(공개 API)이다. 즉 **VPN 없이도 봇 자동화가 돌 수 있다.** 다만 문서·콘솔 열람에는 corp 로그인이 필요하다.

### 무인증 연결성 확인 (실측)
```
POST https://open.popo.netease.com/open-apis/robots/v1/token
{"appKey":"...","appSecret":"..."}
→ 200 {"errcode":41010,"errmsg":"appKey invalid","traceId":"..."}
```
`[공식]` 엔드포인트가 외부에서 살아있고, 표준 `errcode/errmsg/traceId` 규약을 쓴다는 뜻.

---

## 2. 개방플랫폼이 제공하는 것 (문서 트리 실측)

`open.popo.netease.com`의 프론트 번들에서 추출한 **실제 문서 라우트 2,000여 개**를 분류한 결과. `[공식]` (본문은 SSO 뒤라 미열람)

| 영역 | 경로 | 내용 |
|---|---|---|
| **机器人(봇)** | `/docs/robot/*` | 봇 종류·발급, access-token, message/instruction/team/onboard/viewscope API, **이벤트 구독(HTTP 콜백 · 롱커넥션)**, 롱커넥션 **Java SDK / Python SDK** |
| **서버 API** | `/docs/server/*` | 메시지 발송(text/file/card/template), 자동응답, 읽음, 메시지 이벤트, 커스텀 메뉴, **API rate limit·응답코드 규약** |
| **업무 데이터** | `/docs/api/*` | **cloud-zone**(문서·폴더·팀스페이스·업로드·**mtable 다차원표**: record/field/view/cell/dashboard), **calendar**, **boss-approval(결재)**, api-hub, 커스텀 속성 |
| **프론트 확장** | `/docs/mp`, `/docs/h5`, `/docs/card`, `/docs/blitz-card`, `/docs/application` | 미니프로그램·H5·메시지 카드. IM/연락처/캘린더/파일/디바이스 브릿지 + **AI 관련 브릿지**(`sendAiMessage`, `fillAiSendbox`, `openAiSearchRecords`) |
| **공통 서비스** | `/docs/common-service/*` | POPO QR코드(스캔 로그인·출입·URL 서명), 대화 열기 |
| **디자인 시스템** | `/design/*` | 컬러·타이포·아이콘·간격·다크모드 규격 |

> 우리 업무에 특히 쓸모 있는 건 **cloud-zone의 mtable(다차원표)** — artist-pickup 점수 결과를 사내 표로 자동 적재할 수 있는 자리다.

---

## 3. 봇 2종 — 실제 프로토콜

`[교차]` 아래 요청/응답 형태는 **공개 GitHub의 실사용 코드**에서 확인한 것이다. 공식 문서(SSO 뒤)로 반드시 재확인할 것.

### 3-1. 커스텀 웹훅 봇 — *가장 빠른 길, 발신 전용*
```
POST https://open.popo.netease.com/open-apis/robots/v1/hook/<TOKEN>
Content-Type: application/json
{"message": "본문", "timestamp": "<ms>", "signData": "<base64>"}
```
- 서명(선택): `HMAC-SHA256(key = "{timestamp}\n{secret}", msg = "")` → base64. *(키에 문자열을 넣고 메시지를 비우는 비표준 방식 — 실사용 코드 기준)*
- 이미지: 마크다운 `![](url)` → POPO 형식 `[img]url[/img]`로 변환 필요
- 응답: `{"errcode":0,...}` / 0이 아니면 실패
- **관문**: 그룹 관리자가 그룹에서 봇 추가 → 웹훅 URL 발급. 앱 심사 불필요.
- 출처: [`popo_open_platform_dify_plugin`](https://github.com/w2534073922/popo_open_platform_dify_plugin) (네이즈 사번 메일 명시), [`leonetease/deploymentcheck`](https://github.com/leonetease/deploymentcheck)

### 3-2. 애플리케이션 봇 — *양방향, 제대로 된 길*
**① 토큰 발급**
```
POST /open-apis/robots/v1/token   {"appKey":..., "appSecret":...}
→ data.accessToken   (실사용 캐시 TTL 2시간)
```
**② 발신**
```
POST /open-apis/robots/v1/im/send-msg
Header: Open-Access-Token: <accessToken>
{"receiver":"<corp메일 | 5~10자리 群号>",
 "msgType":"rich_text",
 "message":{"content":[{"tag":"at","email":"..."},{"tag":"text","text":"..."}]}}
```
- `receiver`는 **corp 이메일**(예: `xx@mesg.corp.netease.com`) 또는 **숫자 群号**
- 토큰 만료 시 `access token expired` → 재발급 후 1회 재시도가 관용 패턴

**③ 수신 — 두 가지 방식**
| 방식 | 형태 | 언제 |
|---|---|---|
| HTTP 콜백 | POPO가 내 서버로 GET(검증)/POST(이벤트). 쿼리 `signature/timestamp/nonce/encrypt` 서명 검증 → GET엔 `aes_cbc_encrypt("success")` 응답 | 공개 URL 있는 서버가 있을 때 |
| **롱커넥션(STOMP)** | `wss://nws.popo.netease.com:11012/stomp?auth_token=<onceToken>`, 구독 destination `/robots/msg/<robotUid>`, 하트비트 ~10s | **공개 URL 없이 노트북/사내 서버에서 돌릴 때 → 우리에게 이쪽이 맞다** |

**④ 이벤트 복호화**: `ROBOT_EVENT`의 `data.encrypt`를 **AES-128-CBC**로 복호화. `aesKey`는 **정확히 32자**, 앞 16자 = key, 뒤 16자 = IV.
- 출처: [`godsir/openloom` popoChannel.ts](https://github.com/godsir/openloom) — "moltbot-popo v2.1.13 역분석" 주석 명시

### 3-3. 봇이 **읽을 수 있는 범위** — 확정 (중요)

> 질문: "내 계정에 올라온 방들의 대화를 Claude가 읽을 수 있나?" → **아니다.**

봇이 받는 **이벤트 타입은 딱 4종**이고 전부 "봇에게 온 것"이다. `[교차]` (출처: dify 플러그인 `models/popo_bot_callback_structures.py`)

| 이벤트 | 뜻 |
|---|---|
| `IM_P2P_TO_ROBOT_MSG` | 사용자가 **봇에게 직접** 보낸 1:1 메시지 |
| `IM_CHAT_TO_ROBOT_AT_MSG` | 그룹에서 **봇을 @멘션한** 메시지 |
| `IM_P2P_USER_RECALL_MSG` / `IM_CHAT_USER_RECALL_AT_MSG` | 위 둘의 철회 |

**안 오는 것**: 내 1:1 대화 · 내가 속한 그룹의 일반 대화 · 구독 채널(OA/KM 등) · 봇 합류 **이전** 히스토리.
→ **봇은 "나"가 아니라 별도 인격.** 내 계정 권한을 물려받지 않는다. "사내 대화를 긁어 분석"은 설계상 불가능한 방향.

**전달(forward)은 통째로 받는다** — 이벤트 구조에 `merge_list`/`merge_title`(합병 전달), `file_info`(파일명·크기·`file_id`·md5), `quote_info`(인용)가 있다. 즉 **POPO 안에서 대화 뭉치나 문서를 봇 1:1방으로 전달하면 봇이 다 받는다.** 번역·요약 워크플로의 근거.

**방식은 조회가 아니라 푸시**: 봇이 방을 훑는 게 아니라 이벤트 발생 시 POPO가 밀어준다(HTTP 콜백 또는 STOMP). 문서 트리에 `/docs/api/robot/msg-history`가 있으나 `msg-send`·`msg-ack`·`msg-recall`과 같은 묶음이라 **봇 자신의 대화 히스토리** 조회로 추정(미검증). 파일 실물 다운로드는 `/docs/api/robot/msg-file` 필요.

### 3-4. 설계 원칙 — **"봇은 나에게만 말한다"**

> 봇은 **나와의 1:1방에서만 응답**한다. 그룹에는 아무것도 보내지 않는다.
> 답변 초안은 **만들어만 주고, 실제 발송은 사람이 손으로** 한다.

이유: ① 동료에게 오발송될 위험이 구조적으로 0 ② 컴플라이언스 부담 최소 ③ 권한 신청 시 설명이 깔끔해짐("개인 보조용, 그룹 발송 없음") — 신입이 신청해도 통과 확률이 높다.

---

## 4. Claude에 붙이는 방법 (추천 순)

1. **MCP 서버로 감싸기 (본命)** — POPO 봇 API를 감싼 로컬 MCP 서버를 만들어 Claude Code에 연결. 발신은 `send-msg`, 수신은 STOMP 롱커넥션. `.env`에 appKey/appSecret/aesKey. → *우리 프로젝트의 "딜리버리 스킬" 패턴과 정확히 같은 구조: 코어는 그대로, POPO는 출력 채널 하나 추가.*
2. **웹훅 한 줄 알림부터** — 심사 없이 오늘 당장 가능. artist-pickup 리포트 완성 시 그룹에 요약 push.
3. **n8n 경유** — 공개 npm에 **`n8n-nodes-popo`**("POPO Open Platform API and POPO OA API", repo = `gitlab.corp.youdao.com`, 2025-10 갱신)가 있다. 사내 팀이 이미 n8n으로 POPO 자동화를 돌린다는 증거. 코드 없이 반자동화하려면 이 경로.
4. **Dify 플러그인 참고** — 위 dify 플러그인이 발신+콜백+서명검증 전체를 담고 있어 **레퍼런스 구현**으로 가장 유용.
5. **데스크톱 UI 자동화 (최후수단)** — Claude의 computer-use로 POPO 앱을 직접 클릭·타이핑. 기술적으론 가능하나 **깨지기 쉽고 사내 보안정책 위반 소지**. 공식 API가 있는 이상 쓸 이유가 없다.

---

## 5. 제약 · 주의

- **문서·콘솔 = corp SSO 전용.** `open.popo.netease.com/docs/*` 접속 시 `login.netease.com`(网易内部认证系统, corp 메일 접두어 + 비밀번호/동적 비밀번호)로 리다이렉트. `[공식]` — **Claude가 대신 로그인하지 않는다. 사내 계정 자격증명은 사용자 본인만 입력한다.**
- **앱/봇 등록에 심사가 있다.** 문서에 `/docs/robot/start/robot-api-apply`(봇 API 신청), `/docs/server/development-process`(개발 프로세스) 라우트 존재. `[공식]`
- **Rate limit 규약 존재** — `/docs/server/intro/api_limit`. 대량 발송 전 확인 필수. `[공식]`
- **공개 SDK 없음** — PyPI `popo*` 전부 404, npm에도 공식 SDK 없음. 롱커넥션 Java/Python SDK는 **개방플랫폼 내부 배포**로 보인다. `[공식]`
- **컴플라이언스 (우리 원칙 #2와 직결)**: 사내 데이터(계약 조건·아티스트 협상 정보)를 외부 SaaS로 흘리지 않는다. POPO에서 읽은 것은 로컬에서 처리하고, 필요한 최소만 남긴다. 사내 정보보안 규정 우선.
- **GitHub에 실 웹훅 토큰이 다수 노출돼 있다** (검색으로 5건 이상 발견). 우리 토큰은 절대 커밋하지 않는다 — `.env`만.

---

## 6. 다음에 확인할 것 (SSO 로그인 후)

사용자가 corp 계정으로 로그인해서 아래를 열어보면 이 문서의 `[교차]`가 전부 `[공식]`이 된다:

1. `open.popo.netease.com/docs/robot/start/robot-type` — 봇 종류·차이
2. `.../docs/robot/start/robot-api-apply` — **신청 절차·소요 기간·필요 승인자**
3. `.../docs/robot/start/event-subscribe/long-connection/python-sdk` — **Python SDK 실물**
4. `.../docs/server/intro/api_limit` — rate limit 수치
5. `.../docs/api/cloud-zone/mtable/*` — 다차원표 API (artist-pickup 결과 적재용)
6. `.../docs/server/msg/msg-card` — 리치 카드 포맷 (리포트 요약 카드용)
