# 30 · 참고 구현 — 사이트가 DB 를 읽고, /admin 이 고친다 (Next.js App Router)

## src/lib/supabase.ts — 서버 전용
```ts
import "server-only";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
let cached: SupabaseClient | null = null;
export function hasSupabaseEnv() { return Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY); }
export function db(): SupabaseClient {
  if (cached) return cached;
  const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 가 없습니다. Vercel 연동을 확인하세요.");
  cached = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  return cached;
}
```
브라우저에서 실행되는 파일("use client")이 이 파일을 import 하면 안 된다. service_role 키는 RLS 를 무시하는 관리자 키다.

## src/lib/content.ts — 사이트가 읽는 헬퍼
```ts
import "server-only";
import { db, hasSupabaseEnv } from "@/lib/supabase";
export type ContentRow = { key: string; type: "text"|"longtext"|"list"|"toggle"; label: string; value: unknown; sort: number; updated_at: string };
/** 한 항목. DB 에 없거나 env 가 없으면 fallback(코드에 있던 원래 값). 그래서 DB 가 꺼져도 사이트는 뜬다. */
export async function getContent<T>(key: string, fallback: T): Promise<T> {
  if (!hasSupabaseEnv()) return fallback;
  const { data } = await db().from("site_content").select("value").eq("key", key).maybeSingle<{ value: T }>();
  return (data?.value as T) ?? fallback;
}
export async function getAllContent(): Promise<ContentRow[]> {
  const { data } = await db().from("site_content").select("*").order("sort");
  return (data ?? []) as ContentRow[];
}
```
## 사이트 컴포넌트에서 쓰는 패턴 (서버 컴포넌트)
```tsx
// app/page.tsx
import { getContent } from "@/lib/content";
export const dynamic = "force-dynamic";   // 저장 즉시 반영. 캐시하면 어드민에서 바꿔도 안 보인다.
export default async function Home() {
  const title = await getContent("hero_title", "나를 소개합니다");        // 두 번째 인자 = 코드에 있던 원래 값
  const links = await getContent<{label:string;url:string}[]>("links", []);
  const recruiting = await getContent("recruiting", true);
  return (<main>
    <h1>{title}</h1>
    {recruiting && <p>모집 중</p>}
    <ul>{links.map(l => <li key={l.url}><a href={l.url}>{l.label}</a></li>)}</ul>
  </main>);
}
```
바꾸는 건 **값을 가져오는 줄**뿐이다. JSX 구조·className·색은 그대로 둔다.

## 환경변수
ADMIN_PASSCODE (서버 전용. 12자 이상 권장), ADMIN_SESSION_SECRET (32자 이상 랜덤. 쿠키 서명용)
둘 다 Vercel Production 에만. 값은 사용자가 직접 넣는다.

## src/lib/admin-auth.ts
```ts
import { createHmac, timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";

const COOKIE = "admin_session";
const TTL_SEC = 60 * 60 * 12; // 12시간

function secret(): string {
  const s = process.env.ADMIN_SESSION_SECRET;
  if (!s || s.length < 32) throw new Error("ADMIN_SESSION_SECRET 이 없거나 32자 미만");
  return s;
}
function sign(payload: string): string {
  return createHmac("sha256", secret()).update(payload).digest("base64url");
}
/** 세션 토큰 = 만료시각.서명 */
export function issueSession(): { value: string; maxAge: number } {
  const exp = String(Math.floor(Date.now() / 1000) + TTL_SEC);
  return { value: `${exp}.${sign(exp)}`, maxAge: TTL_SEC };
}
export function verifySession(token: string | undefined): boolean {
  if (!token) return false;
  const [exp, sig] = token.split(".");
  if (!exp || !sig) return false;
  if (Number(exp) < Math.floor(Date.now() / 1000)) return false;
  const a = Buffer.from(sign(exp)); const b = Buffer.from(sig);
  return a.length === b.length && timingSafeEqual(a, b);
}
/** 비밀번호 비교. 길이가 달라도 timing-safe 하게. */
export function checkPasscode(input: string): boolean {
  const want = process.env.ADMIN_PASSCODE ?? "";
  if (!want) return false;
  const a = Buffer.from(input); const b = Buffer.from(want);
  if (a.length !== b.length) { timingSafeEqual(b, b); return false; }
  return timingSafeEqual(a, b);
}
function readCookie(req: Request): string | undefined {
  const raw = req.headers.get("cookie") ?? "";
  const m = raw.match(new RegExp(`(?:^|;\\s*)${COOKIE}=([^;]+)`));
  return m?.[1];
}
/** 관리용 API 라우트 첫 줄에서 호출. 통과면 null, 아니면 401 응답. */
export function requireAdmin(req: Request): NextResponse | null {
  if (verifySession(readCookie(req))) return null;
  return NextResponse.json({ error: "unauthorized" }, { status: 401, headers: { "Cache-Control": "no-store" } });
}
export const ADMIN_COOKIE = COOKIE;
```

## src/lib/rate-limit.ts — 인메모리 속도 제한
```ts
/**
 * 아주 단순한 인메모리 rate limit.
 * Vercel 서버리스에서는 인스턴스별로 동작하므로 "완벽한" 방어가 아니라
 * 실수·단순 봇을 막는 1차 안전장치다. 트래픽이 커지면 Upstash 등으로 교체.
 */
type Bucket = { count: number; resetAt: number };
const buckets = new Map<string, Bucket>();

export function rateLimit(
  key: string,
  { limit = 5, windowMs = 60_000 }: { limit?: number; windowMs?: number } = {},
): { ok: boolean; retryAfterSec: number } {
  const now = Date.now();
  const b = buckets.get(key);
  if (!b || b.resetAt <= now) {
    buckets.set(key, { count: 1, resetAt: now + windowMs });
    return { ok: true, retryAfterSec: 0 };
  }
  b.count += 1;
  if (b.count > limit) {
    return { ok: false, retryAfterSec: Math.ceil((b.resetAt - now) / 1000) };
  }
  return { ok: true, retryAfterSec: 0 };
}

// 메모리 누수 방지: 가끔 만료된 버킷 정리
if (typeof setInterval === "function") {
  const t = setInterval(() => {
    const now = Date.now();
    for (const [k, b] of buckets) if (b.resetAt <= now) buckets.delete(k);
  }, 5 * 60_000);
  // Node에서 프로세스 종료를 막지 않도록
  (t as { unref?: () => void }).unref?.();
}
```
`admin-login`(`src/app/api/admin/login/route.ts`)과 `inquiry`(`src/app/api/inquiries/route.ts`) 두 라우트가 이 구현을 공유한다. 키 prefix만 다르게 줘서 버킷이 섞이지 않게 한다.

## src/app/api/admin/login/route.ts
```ts
import { NextResponse } from "next/server";
import { checkPasscode, issueSession, ADMIN_COOKIE } from "@/lib/admin-auth";
import { rateLimit } from "@/lib/rate-limit";
export const runtime = "nodejs";
export async function POST(req: Request) {
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  const rl = rateLimit(`admin-login:${ip}`, { limit: 5, windowMs: 10 * 60_000 });
  if (!rl.ok) return NextResponse.json({ error: "too_many" }, { status: 429 });
  const body = await req.json().catch(() => ({}));
  const pass = typeof body?.passcode === "string" ? body.passcode.slice(0, 200) : "";
  if (!checkPasscode(pass)) return NextResponse.json({ error: "invalid" }, { status: 401 });
  const s = issueSession();
  const res = NextResponse.json({ ok: true });
  res.cookies.set(ADMIN_COOKIE, s.value, { httpOnly: true, secure: true, sameSite: "lax", path: "/", maxAge: s.maxAge });
  return res;
}
```

## src/app/api/admin/logout/route.ts
```ts
import { NextResponse } from "next/server";
import { ADMIN_COOKIE } from "@/lib/admin-auth";
export async function POST() {
  const res = NextResponse.json({ ok: true });
  res.cookies.set(ADMIN_COOKIE, "", { httpOnly: true, secure: true, sameSite: "lax", path: "/", maxAge: 0 });
  return res;
}
```

## src/middleware.ts (페이지 보호. /admin/* 와 /api 의 관리용 경로)
```ts
import { NextResponse, type NextRequest } from "next/server";
// Edge 런타임에서는 node:crypto 를 못 쓰므로 여기서는 쿠키 존재만 보고, 실제 검증은 각 라우트의 requireAdmin 이 한다.
// 페이지는 서버 컴포넌트 첫 줄에서 verifySession 을 다시 호출한다(아래 page 예시).
export function middleware(req: NextRequest) {
  const p = req.nextUrl.pathname;
  const protectedPage = p.startsWith("/admin") && p !== "/admin/login";
  if (protectedPage && !req.cookies.get("admin_session")?.value) {
    const url = req.nextUrl.clone(); url.pathname = "/admin/login"; url.searchParams.set("next", p);
    return NextResponse.redirect(url);
  }
  return NextResponse.next();
}
export const config = { matcher: ["/admin/:path*"] };
```

## src/app/admin/login/page.tsx (서버 컴포넌트 + 작은 클라이언트 폼)
```tsx
import { LoginForm } from "@/components/LoginForm";
export const metadata = { robots: { index: false, follow: false } };
export default function LoginPage() { return <main style={{maxWidth:360,margin:"80px auto"}}><h1>관리자</h1><LoginForm /></main>; }
```
```tsx
"use client";
import { useState } from "react";
export function LoginForm() {
  const [pass, setPass] = useState(""); const [err, setErr] = useState("");
  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const r = await fetch("/api/admin/login", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ passcode: pass }) });
    if (r.ok) { const next = new URLSearchParams(location.search).get("next") || "/admin"; location.href = next.startsWith("/admin") ? next : "/admin"; }
    else setErr(r.status === 429 ? "잠시 후 다시 시도해 주세요." : "비밀번호가 맞지 않습니다.");
  }
  return <form onSubmit={submit}><input type="password" value={pass} onChange={e=>setPass(e.target.value)} autoComplete="current-password" /><button type="submit">들어가기</button>{err && <p role="alert">{err}</p>}</form>;
}
```
`next` 파라미터는 `/admin` 으로 시작할 때만 따른다(오픈 리다이렉트 방지).

## 보호된 페이지 첫 줄 (서버 컴포넌트)
```tsx
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { verifySession, ADMIN_COOKIE } from "@/lib/admin-auth";
export default async function Page() {
  const c = await cookies();
  if (!verifySession(c.get(ADMIN_COOKIE)?.value)) redirect("/admin/login?next=/admin");
  // …
}
```

## src/app/api/admin/content/route.ts — 편집 저장
```ts
import { NextResponse } from "next/server";
import { db } from "@/lib/supabase";
import { requireAdmin } from "@/lib/admin-auth";
export const runtime = "nodejs";
const MAX = { text: 200, longtext: 5000, list: 50 };
export async function PATCH(req: Request) {
  const denied = requireAdmin(req); if (denied) return denied;
  const body = await req.json().catch(() => null);
  const key = typeof body?.key === "string" ? body.key.slice(0, 64) : "";
  if (!key) return NextResponse.json({ error: "key" }, { status: 422 });
  const { data: row } = await db().from("site_content").select("type").eq("key", key).maybeSingle<{ type: "text" | "longtext" | "list" | "toggle" }>();
  if (!row) return NextResponse.json({ error: "unknown_key" }, { status: 404 });
  let value: unknown = body.value;
  if (row.type === "text" || row.type === "longtext") {
    if (typeof value !== "string") return NextResponse.json({ error: "type" }, { status: 422 });
    value = value.slice(0, MAX[row.type]);
  } else if (row.type === "list") {
    if (!Array.isArray(value) || value.length > MAX.list) return NextResponse.json({ error: "type" }, { status: 422 });
    value = value.map((v) => (typeof v === "string" ? v.slice(0, 200) : (typeof v === "object" && v ? Object.fromEntries(Object.entries(v).slice(0, 6).map(([k, x]) => [k.slice(0, 32), String(x).slice(0, 500)])) : null))).filter(Boolean);
  } else if (row.type === "toggle") {
    if (typeof value !== "boolean") return NextResponse.json({ error: "type" }, { status: 422 });
  }
  const { error } = await db().from("site_content").update({ value, updated_at: new Date().toISOString() }).eq("key", key);
  if (error) return NextResponse.json({ error: "save_failed" }, { status: 500 });
  return NextResponse.json({ ok: true });
}
```
새 key 를 만드는 API 는 없다. 항목은 마이그레이션 seed 로만 늘린다(구조는 어드민에서 못 바꾸게).

## src/app/admin/page.tsx — 편집 화면 (서버 컴포넌트 + 클라이언트 폼)
```tsx
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { verifySession, ADMIN_COOKIE } from "@/lib/admin-auth";
import { getAllContent } from "@/lib/content";
import { ContentEditor } from "@/components/ContentEditor";
export const metadata = { robots: { index: false, follow: false } };
export const dynamic = "force-dynamic";
export default async function AdminPage() {
  const c = await cookies();
  if (!verifySession(c.get(ADMIN_COOKIE)?.value)) redirect("/admin/login?next=/admin");
  const rows = await getAllContent();
  return (<main style={{ maxWidth: 720, margin: "40px auto", padding: 16 }}>
    <h1>관리자</h1>
    <p><a href="/admin/inquiries">문의 접수함</a> · <a href="/" target="_blank">사이트 열기</a></p>
    <ContentEditor rows={rows} />
  </main>);
}
```
```tsx
// src/components/ContentEditor.tsx
"use client";
import { useState } from "react";
type Row = { key: string; type: "text"|"longtext"|"list"|"toggle"; label: string; value: unknown };
export function ContentEditor({ rows }: { rows: Row[] }) {
  const [state, setState] = useState<Record<string, unknown>>(Object.fromEntries(rows.map(r => [r.key, r.value])));
  const [msg, setMsg] = useState<Record<string, string>>({});
  async function save(key: string) {
    setMsg(m => ({ ...m, [key]: "저장 중…" }));
    const r = await fetch("/api/admin/content", { method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify({ key, value: state[key] }) });
    setMsg(m => ({ ...m, [key]: r.ok ? "저장됨 · 사이트를 새로고침하면 보여요" : "저장 실패 (" + r.status + ")" }));
  }
  return (<div style={{ display: "grid", gap: 20 }}>
    {rows.map(r => (<section key={r.key} style={{ border: "1px solid #ddd", padding: 12 }}>
      <label style={{ fontWeight: 700 }}>{r.label}</label>
      {r.type === "text" && <input value={String(state[r.key] ?? "")} onChange={e => setState(s => ({ ...s, [r.key]: e.target.value }))} style={{ width: "100%" }} />}
      {r.type === "longtext" && <textarea rows={6} value={String(state[r.key] ?? "")} onChange={e => setState(s => ({ ...s, [r.key]: e.target.value }))} style={{ width: "100%" }} />}
      {r.type === "toggle" && <label><input type="checkbox" checked={Boolean(state[r.key])} onChange={e => setState(s => ({ ...s, [r.key]: e.target.checked }))} /> 켜기</label>}
      {r.type === "list" && <ListEditor value={(state[r.key] as unknown[]) ?? []} onChange={v => setState(s => ({ ...s, [r.key]: v }))} />}
      <div><button onClick={() => save(r.key)}>저장</button> <small>{msg[r.key]}</small></div>
    </section>))}
  </div>);
}
function ListEditor({ value, onChange }: { value: unknown[]; onChange: (v: unknown[]) => void }) {
  const isObj = value.length > 0 && typeof value[0] === "object";
  const keys = isObj ? Object.keys(value[0] as object) : [];
  const set = (i: number, v: unknown) => onChange(value.map((x, j) => (j === i ? v : x)));
  return (<div style={{ display: "grid", gap: 6 }}>
    {value.map((item, i) => (<div key={i} style={{ display: "flex", gap: 6 }}>
      {isObj ? keys.map(k => <input key={k} placeholder={k} value={String((item as Record<string, unknown>)[k] ?? "")} onChange={e => set(i, { ...(item as object), [k]: e.target.value })} />)
             : <input value={String(item)} onChange={e => set(i, e.target.value)} />}
      <button type="button" onClick={() => onChange(value.filter((_, j) => j !== i))}>빼기</button>
      <button type="button" disabled={i === 0} onClick={() => { const v = [...value]; [v[i-1], v[i]] = [v[i], v[i-1]]; onChange(v); }}>↑</button>
    </div>))}
    <button type="button" onClick={() => onChange([...value, isObj ? Object.fromEntries(keys.map(k => [k, ""])) : ""])}>줄 추가</button>
  </div>);
}
```
"빼기"는 목록의 줄을 화면에서 빼는 것이고, 저장을 눌러야 반영된다. 표 자체를 지우는 기능은 없다.

## 문의 — src/app/api/inquiries/route.ts (공개 쓰기) 와 폼 연결
```ts
import { NextResponse } from "next/server";
import { db, hasSupabaseEnv } from "@/lib/supabase";
import { rateLimit } from "@/lib/rate-limit";
export const runtime = "nodejs";
export async function POST(req: Request) {
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  const rl = rateLimit(`inquiry:${ip}`, { limit: 5, windowMs: 60_000 });
  if (!rl.ok) return NextResponse.json({ error: "too_many" }, { status: 429 });
  const body = await req.json().catch(() => ({}));
  if (typeof body.website === "string" && body.website) return NextResponse.json({ ok: true }); // 허니팟: 봇만 채우는 숨은 칸
  const name = String(body.name ?? "").trim().slice(0, 40), contact = String(body.contact ?? "").trim().slice(0, 80), message = String(body.message ?? "").trim().slice(0, 2000);
  if (name.length < 1 || contact.length < 5) return NextResponse.json({ error: "invalid" }, { status: 422 });
  if (!hasSupabaseEnv()) return NextResponse.json({ error: "db_unavailable" }, { status: 503 });
  const { error } = await db().from("inquiries").insert({ name, contact, message });
  if (error) return NextResponse.json({ error: "save_failed" }, { status: 500 });
  return NextResponse.json({ ok: true });
}
```
폼 컴포넌트에서는 `fetch("/api/inquiries", { method: "POST", body: JSON.stringify({ name, contact, message, website: "" }) })` 로 보내고, `website` 칸은 `<input name="website" style={{display:"none"}} tabIndex={-1} autoComplete="off" />` 로 숨긴다.

## src/app/admin/inquiries/page.tsx + src/app/api/admin/inquiries/route.ts
```tsx
import { cookies } from "next/headers"; import { redirect } from "next/navigation";
import { verifySession, ADMIN_COOKIE } from "@/lib/admin-auth"; import { db } from "@/lib/supabase";
import { InquiryList } from "@/components/InquiryList";
export const metadata = { robots: { index: false, follow: false } }; export const dynamic = "force-dynamic";
export default async function Page() {
  const c = await cookies(); if (!verifySession(c.get(ADMIN_COOKIE)?.value)) redirect("/admin/login?next=/admin/inquiries");
  const { data } = await db().from("inquiries").select("id,name,contact,message,status,created_at").order("created_at", { ascending: false }).limit(200);
  return (<main style={{ maxWidth: 900, margin: "40px auto", padding: 16 }}><h1>문의 접수함</h1><p><a href="/admin">← 관리자</a></p><InquiryList rows={data ?? []} /></main>);
}
```
```tsx
// src/components/InquiryList.tsx
"use client";
import { useState } from "react";
type Row = { id: string; name: string; contact: string; message: string | null; status: "new"|"checked"|"done"; created_at: string };
const LABEL = { new: "새로 옴", checked: "확인", done: "완료" } as const;
export function InquiryList({ rows }: { rows: Row[] }) {
  const [list, setList] = useState(rows);
  async function setStatus(id: string, status: Row["status"]) {
    const r = await fetch("/api/admin/inquiries", { method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify({ id, status }) });
    if (r.ok) setList(l => l.map(x => (x.id === id ? { ...x, status } : x)));
  }
  return (<table style={{ width: "100%", borderCollapse: "collapse" }}><thead><tr><th>언제</th><th>이름</th><th>연락처</th><th>내용</th><th>상태</th></tr></thead>
    <tbody>{list.map(r => (<tr key={r.id} style={{ borderTop: "1px solid #ddd" }}>
      <td>{new Date(r.created_at).toLocaleString("ko-KR")}</td><td>{r.name}</td><td>{r.contact}</td><td style={{ whiteSpace: "pre-wrap" }}>{r.message}</td>
      <td><select value={r.status} onChange={e => setStatus(r.id, e.target.value as Row["status"])}>{(Object.keys(LABEL) as Row["status"][]).map(s => <option key={s} value={s}>{LABEL[s]}</option>)}</select></td>
    </tr>))}</tbody></table>);
}
```
```ts
// src/app/api/admin/inquiries/route.ts
import { NextResponse } from "next/server"; import { db } from "@/lib/supabase"; import { requireAdmin } from "@/lib/admin-auth";
export const runtime = "nodejs";
export async function PATCH(req: Request) {
  const denied = requireAdmin(req); if (denied) return denied;
  const body = await req.json().catch(() => ({}));
  const id = typeof body.id === "string" ? body.id : "", status = body.status;
  if (!id || !["new","checked","done"].includes(status)) return NextResponse.json({ error: "invalid" }, { status: 422 });
  const { error } = await db().from("inquiries").update({ status }).eq("id", id);
  if (error) return NextResponse.json({ error: "save_failed" }, { status: 500 });
  return NextResponse.json({ ok: true });
}
```

## 이 파일이 지키는 것
- 사이트는 `getContent(key, 원래값)` 으로 읽는다. DB 가 꺼져도 원래값으로 뜬다.
- `force-dynamic` 이 없으면 어드민에서 바꿔도 캐시된 옛 화면이 보인다. 워크숍의 "됐다" 순간이 안 온다.
- 편집 API 는 key 를 새로 만들지 못한다. 항목·구조는 코드(마이그레이션)가 정하고, 어드민은 값만 바꾼다.
- 삭제 API 가 없다. 문의는 상태만 바뀐다.
- 로그인·세션·쿠키는 sponge-admin-kit 과 같은 코드라 검증된 그대로다.
