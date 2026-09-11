# 50 · 인수인계 — 끝날 때 이 양식으로

```
# 어드민 인수인계 · (사이트 이름) · (날짜)

사이트: https://…
어드민: https://…/admin  (비밀번호는 Vercel → Settings → Environment Variables → ADMIN_PASSCODE 에 있음. 이 문서에 값은 적지 않는다)

바꿀 수 있는 것
| 항목 | 종류 | 어디에 보이나 |
|---|---|---|
| 메인 제목 | 짧은 글 | 첫 화면 |
| 소개 문구 | 긴 글 | 첫 화면 |
| 외부 링크 | 목록 | 푸터 |
| 모집 중 표시 | 켜고 끄기 | 첫 화면 배지 |
| 문의 접수함 | 접수함 | /admin/inquiries |

안 바꾸는 것: 레이아웃 · 색 · 페이지 구조 (바꾸려면 클로드에게)

표: site_content (항목 N개), inquiries
환경변수 이름: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (Vercel–Supabase 연동이 넣음), ADMIN_PASSCODE, ADMIN_SESSION_SECRET (직접 넣음)
테스트 데이터: inquiries 에 테스트 문의 1건 (이름 "테스트") — 지우려면 Supabase Table Editor 에서

확인한 것
- 어드민에서 (항목) 을 "…" → "…" 로 바꾸고 사이트에서 확인 (스크린샷)
- 테스트 문의 1건이 접수함에 보임
- 자체 점검 5줄 (40-security-lite)

오늘 막힌 것 / 다음에 할 것
- …
```
스크린샷은 문서와 같은 폴더에 둔다. 값(키·비밀번호)은 어디에도 적지 않는다.
