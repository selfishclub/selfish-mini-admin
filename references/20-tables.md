# 20 · 냉장고 만들기 — 표와 Supabase 연동

어드민은 냉장고 문이다. 어드민으로 바꾸려면 그 내용이 DB에 있어야 한다. 코드에 글자로 박혀 있으면 못 바꾼다.

## 표 두 개 (필요한 것만)
```sql
-- supabase/migrations/20260911000001_site_content.sql
create table if not exists public.site_content (
  key        text primary key,            -- 'hero_title', 'links', 'recruiting'
  type       text not null default 'text' -- 'text' | 'longtext' | 'list' | 'toggle'
    check (type in ('text','longtext','list','toggle')),
  label      text not null,               -- 어드민에 보일 이름 '메인 제목'
  value      jsonb not null,              -- "문자열" | ["a","b"] | true
  sort       integer not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.site_content enable row level security;
revoke all on public.site_content from anon, authenticated;
grant select, insert, update on public.site_content to service_role;
```
```sql
-- supabase/migrations/20260911000002_inquiries.sql  (폼이 있을 때만)
create table if not exists public.inquiries (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  contact    text not null,               -- 전화 또는 이메일, 원문 그대로
  message    text,
  status     text not null default 'new' check (status in ('new','checked','done')),
  created_at timestamptz not null default now()
);
alter table public.inquiries enable row level security;
revoke all on public.inquiries from anon, authenticated;
grant select, insert, update on public.inquiries to service_role;   -- delete 없음
```
표 생성과 RLS·권한 회수가 같은 파일에 있어야 한다. 정책(policy)은 만들지 않는다. 그러면 브라우저 키(anon)로는 아무것도 못 읽고 못 쓴다. 읽고 쓰는 건 서버 API 뿐이다.

## seed — 코드에 박힌 값을 옮긴다
```sql
insert into public.site_content (key, type, label, value, sort) values
 ('hero_title',  'text',     '메인 제목',   '"나를 소개합니다"', 1),
 ('hero_intro',  'longtext', '소개 문구',   '"…"', 2),
 ('links',       'list',     '외부 링크',   '[{"label":"인스타그램","url":"https://…"}]', 3),
 ('recruiting',  'toggle',   '모집 중 표시', 'true', 4)
on conflict (key) do nothing;
```
값은 00-detect 7번에서 찾은 실제 문자열을 그대로 넣는다. 지어내지 않는다.

## DB 가 없을 때 — AI가 브라우저로 직접 하는 순서
사용자가 Supabase·Vercel 에 로그인돼 있어야 한다. 가입·결제·플랜 변경은 하지 않는다.
1. supabase.com/dashboard → New project → 이름은 사이트 이름, 리전 Northeast Asia (Seoul), DB 비밀번호는 "Generate" 버튼으로 생성하고 **복사하거나 출력하지 않는다** → Create.
2. 프로젝트가 켜질 때까지 기다린다(1~2분).
3. Vercel 연동: Supabase 대시보드 → 프로젝트 → Integrations → Vercel → Add new project connection → 사이트의 Vercel 프로젝트 선택 → Production 체크 → Connect. 이러면 `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` 등이 Vercel 환경변수로 자동 들어간다. 키를 사람이 옮기지 않는다.
   (Vercel 쪽에서 하려면: Vercel 프로젝트 → Storage → Connect Database → Supabase 가 목록에 있을 때만.)
4. 표 만들기: Supabase → SQL Editor → 새 쿼리 → 위 SQL 붙여 넣기 → Run. 붙여 넣기는 `javascript_tool` 로 `monaco.editor.getModels().at(-1).setValue(sql)` 가 확실하다. "Potential issue" 창이 뜨면 "Run query".
5. 확인: Table Editor 에 표 2개가 보이고, 각 표의 RLS 배지가 켜져 있다. 스크린샷.
6. 로컬 개발용: Vercel 에 연동된 뒤 `vercel env pull .env.local` (시크릿은 `[SENSITIVE]` 로 내려올 수 있다. 그러면 로컬은 건너뛰고 배포로 확인한다).
7. 재배포: 빈 커밋 push. 환경변수는 다음 배포부터 적용된다.

## 어드민 비밀번호
Vercel → 프로젝트 → Settings → Environment Variables → `ADMIN_PASSCODE`(12자 이상), `ADMIN_SESSION_SECRET`(32자 이상 랜덤) → Production 만 체크. **값은 사용자가 직접 입력한다.** AI는 입력창에 타이핑하지 않는다. 랜덤 값이 필요하면 `openssl rand -base64 32` 를 사용자에게 알려 준다.
