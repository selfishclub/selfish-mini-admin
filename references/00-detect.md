# 00 · 환경 파악 (워크숍판)

코드를 쓰기 전에 아래 10개를 저장소에서 읽어 표로 보여 준다. 값(키·비밀번호)은 절대 출력하지 않는다. 표를 보여 준 뒤 "틀린 곳이 있으면 고쳐 주세요. 맞으면 진행합니다."라고 묻는다.

| # | 항목 | 보는 곳 | 결과 예 |
|---|---|---|---|
| 1 | 프레임워크 | package.json dependencies (next / vite / astro / 정적 html) | Next.js 16 (App Router) |
| 2 | 배포 | .vercel/, vercel.json, README 의 주소 | Vercel, https://… |
| 3 | 저장소 | .git 과 origin | GitHub 연결됨 / 안 됨 |
| 4 | DB 유무 | @supabase/supabase-js, supabase/ 폴더, SUPABASE_URL 같은 변수 이름, firebase.json | 없음 → 3단계에서 Supabase 를 붙인다 |
| 5 | 페이지 목록 | app/**/page.tsx, pages/*.tsx, *.html | /, /about, /contact |
| 6 | 폼 유무 | `<form`, onSubmit, fetch('/api/…') | 문의 폼 있음 (/contact) → 저장 안 됨(콘솔만) |
| 7 | 코드에 박힌 문구·목록 | 페이지·컴포넌트의 문자열 상수, 배열, JSON | 제목·소개·가격 3개, 링크 배열 1개, FAQ 배열 1개 |
| 8 | 설계도 파일 | docs/, 루트의 *.md 중 PRD·설계도·v3 | 설계도_v3.md 있음 |
| 9 | 환경변수 이름 | .env.example, process.env.* (이름만) | NEXT_PUBLIC_SITE_URL |
| 10 | 어드민 유무 | /admin 경로, middleware | 없음 |

## 명령 (저장소 루트)
```bash
cat package.json | head -40; ls .vercel vercel.json supabase 2>/dev/null; git remote -v | head -1
find . -path ./node_modules -prune -o \( -name "page.tsx" -o -name "page.js" -o -name "*.html" \) -print | head -30
grep -rlE "<form|onSubmit" src app 2>/dev/null | head
grep -rhoE "process\.env\.[A-Z0-9_]+" src app 2>/dev/null | sort -u
ls docs *.md 2>/dev/null
```

## 7번을 뽑는 요령
- 컴포넌트 안의 한국어 문자열 상수(제목·소개·가격·공지), 3개 이상 요소를 가진 배열(링크·FAQ·메뉴·프로젝트), `true/false` 로 켜고 끄는 값(모집중, 배너)을 찾는다.
- 파일과 줄 번호를 같이 적는다. 다음 단계(10-judge) 의 재료다.

## DB 프로젝트를 다른 사이트와 같이 쓰는 경우
4번에서 이미 Supabase 가 있고 표 이름에 다른 서비스 것이 섞여 있으면, 이 사이트 표에 접두사(예 `mysite_`)를 붙이자고 제안한다. 워크숍 기본은 사이트당 프로젝트 하나라 접두사 없이 `site_content`, `inquiries` 를 쓴다.
