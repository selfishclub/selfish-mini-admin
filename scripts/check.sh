#!/usr/bin/env bash
set -u; cd "$(dirname "$0")/.."; fail=0; say(){ echo "✗ $1"; fail=1; }
head -1 SKILL.md | grep -q '^---$' || say "frontmatter 없음"
grep -q '^name: selfish-mini-admin$' SKILL.md || say "name 불일치"
grep -q '^description: .\{80,\}' SKILL.md || say "description 80자 미만"
grep -q '^license:' SKILL.md || say "license 없음"; grep -q '^version:' SKILL.md || say "version 없음"
for f in 00-detect 10-judge 20-tables 30-impl-admin 40-security-lite 50-handoff; do
  [ -f "references/$f.md" ] || say "references/$f.md 없음"
  grep -q "references/$f.md" SKILL.md || say "SKILL.md가 references/$f.md 를 언급하지 않음"
done
grep -rniE 'vetd|first100|zemma|G-SJH91732LJ|tvrmejtgyjxmklytuzmb' SKILL.md references README.md CHANGELOG.md >/dev/null && say "금지 문자열 발견: $(grep -rniE 'vetd|first100|zemma' SKILL.md references README.md | head -2)"
grep -rnE 'eyJ[A-Za-z0-9_-]{20,}|sk_(live|test)_[A-Za-z0-9]{10,}' . --include=*.md >/dev/null && say "키처럼 보이는 문자열"
grep -rniE 'utm_|google analytics|gtag' SKILL.md references >/dev/null && say "범위 밖(UTM/GA) 언급"
lines=$(wc -l < SKILL.md); [ "$lines" -le 200 ] || say "SKILL.md ${lines}줄 (200 초과)"
grep -rnE 'TBD|TODO|작성 중' SKILL.md references README.md >/dev/null && say "플레이스홀더 남음"
[ $fail -eq 0 ] && echo "✓ check passed"; exit $fail
