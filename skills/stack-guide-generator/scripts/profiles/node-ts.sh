#!/bin/bash
# profiles/node-ts.sh — pack-smoke.sh의 Node/TypeScript 프로필
#
# 프로필 계약은 함수 하나다: profile_check <작업디렉토리>.
# 그 안에서 이 툴체인이 할 수 있는 검사를 돌리고 ok/warn/bad/skip으로 보고한다
# (그 4함수와 num()은 pack-smoke.sh가 정의한다). 종료 코드를 만들지 않는다 —
# 판정 합산은 호출자가 한다.
#
# **의존성이 없으면 skip을 명시 보고한다.** 침묵 통과는 "검사했는데 깨끗함"과
# 구분되지 않고, 그것이 이 하네스가 대체하려는 실패 모드다.

profile_check() {
  local OUT="$1"
  [ -s "$OUT/.units.tsv" ] || { skip "복원 단위 없음 — 검사 대상 없음"; return 0; }
  command -v node >/dev/null 2>&1 || { skip "node 없음 — 구문·타입 검사 생략"; return 0; }

  # ── 구문: 네트워크 없이 돌아간다 ──
  # Node의 stripTypeScriptTypes로 타입을 벗긴 뒤 파싱한다. `--check`는 타입 스트리핑을
  # 적용하지 않아 정상 TS를 전부 구문 오류로 판정한다(개발 중 실측) — 쓰지 않는다.
  #
  # 경로를 주장하는 펜스가 전부 완전한 파일인 것은 아니다. `resolve: { alias: ... }`
  # 같은 설정 조각이 실재하는 관용구다. 조각을 구문 오류로 판정하면 위양성이 되고,
  # 반대로 전부 눈감으면 진짜 절단면을 놓친다. 그래서 **표준 삽입 문맥에 넣어 파싱되면
  # 조각, 어디에도 안 들어가면 구문 오류**로 가른다.
  cat > "$OUT/.classify.mjs" <<'CLS'
import { stripTypeScriptTypes } from 'node:module';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
const dir = process.argv[2];
const only = process.argv.slice(3);
const strips = (code) => { try { stripTypeScriptTypes(code, { mode: 'strip' }); return true; } catch { return false; } };
const files = only.length ? only : readdirSync(dir).sort();
for (const f of files) {
  const src = readFileSync(join(dir, f), 'utf8');
  // JSX와 SFC는 타입 스트리핑 대상이 아니다 — 판정하지 않고 미검사로 보고한다.
  if (/\.(tsx|jsx|vue|svelte)$/.test(f))              { console.log(`UNSUP\t${f}\tJSX/SFC는 스트리핑 대상이 아니다`); continue; }
  // 이 툴체인이 파싱하지 않는 형식 — `check_fence_imports`는 이미 데이터 파일로 예외
  // 처리하는데 분류기만 짝이 안 맞아 `firestore.rules`가 구문 오류로 잡혔다 (C1 실측).
  if (/\.(rules|ya?ml|toml|sql|env|ini|cfg|txt|md|graphql|prisma|html?|css|scss|sass|less|svg)$/.test(f)) {
    console.log(`UNSUP\t${f}\t이 툴체인이 파싱하지 않는 형식`); continue;
  }
  if (/\.json$/.test(f)) {
    const noComments = src.replace(/^\s*\/\/.*$/gm, '');
    try { JSON.parse(noComments); console.log(`FILE\t${f}`); }
    catch (e) { console.log(`FRAG\t${f}\tJSON 조각 또는 주석 포함`); }
    continue;
  }
  if (strips(src))                                    { console.log(`FILE\t${f}`); continue; }
  if (strips(`const __o = {\n${src}\n};`))            { console.log(`FRAG\t${f}\t객체 조각`); continue; }
  if (strips(`function __f() {\n${src}\n}`))          { console.log(`FRAG\t${f}\t문(statement) 조각`); continue; }
  if (strips(`class __C {\n${src}\n}`))               { console.log(`FRAG\t${f}\t클래스 본문 조각`); continue; }
  let msg = '';
  try { stripTypeScriptTypes(src, { mode: 'strip' }); } catch (e) { msg = String(e.message).split('\n')[0]; }
  // strip-only 모드가 **거부하지만 정상 TypeScript**인 문법이 있다 — enum · namespace ·
  // 파라미터 프로퍼티는 타입 제거만으로 지울 수 없어(코드를 생성한다) Node가 막는다.
  // 이것을 구문 오류로 세면 정상 팩이 FAIL한다 (aws-serverless 파일럿이 경고).
  if (/not supported in strip-only mode/.test(msg)) { console.log(`UNSUP\t${f}\t${msg}`); continue; }
  console.log(`SYNTAX\t${f}\t${msg}`);
}
CLS

  # 완전 파일을 주장한 단위만 검사한다. 라벨 단위는 조각인 것이 정상이므로
  # 구문 오류로 판정하면 전부 위양성이 된다 (개발 중 실측: 5개 팩에서 24건).
  local claimed; claimed=$(awk -F'\t' '$5=="file" {print $1}' "$OUT/.units.tsv" | tr '\n' ' ')
  if [ -z "$(printf '%s' "$claimed" | tr -d ' ')" ]; then
    skip "완전 파일 주장 0개 — 구문·타입 검사 생략" "라벨(// 경로)만으로는 완전한 파일인지 알 수 없다. <!-- file: 경로 -->로 주장한 펜스만 검사한다"
    return 0
  fi
  # shellcheck disable=SC2086
  node "$OUT/.classify.mjs" "$OUT/units" $claimed 2>/dev/null > "$OUT/.classify.tsv"
  if [ ! -s "$OUT/.classify.tsv" ]; then
    skip "구문 분류 실행 불가" "node ${$(node --version 2>/dev/null)}가 stripTypeScriptTypes를 지원하지 않는다 (Node 22.13+ 필요)"
    return 0
  fi

  local nfile nfrag nsyn nuns v u msg pth
  nfile=$(num "$(grep -c '^FILE' "$OUT/.classify.tsv" | tr -d ' ')")
  nfrag=$(num "$(grep -c '^FRAG' "$OUT/.classify.tsv" | tr -d ' ')")
  nsyn=$(num "$(grep -c '^SYNTAX' "$OUT/.classify.tsv" | tr -d ' ')")
  nuns=$(num "$(grep -c '^UNSUP' "$OUT/.classify.tsv" | tr -d ' ')")
  [ "$nuns" -gt 0 ] && skip "구문 미검사 ${nuns}개" "$(awk -F'\t' '$1=="UNSUP"{printf "%s(%s) ", $2, substr($3,1,40)}' "$OUT/.classify.tsv")— Node의 타입 스트리핑이 다루지 못하는 문법(JSX·SFC·enum·namespace·파라미터 프로퍼티)이다. **정상 TypeScript일 수 있다** — tsc가 있는 환경(감사 A)에서만 판정된다"
  [ "$nfrag" -gt 0 ] && warn "완전 파일이라 주장했으나 조각 ${nfrag}개" "$(awk -F'\t' '$1=="FRAG"{printf "%s(%s) ", $2, $3}' "$OUT/.classify.tsv")— <!-- file: --> 대신 라벨(// 경로)을 쓰거나, 펜스를 완전한 파일로 만든다"

  if [ "$nsyn" -gt 0 ]; then
    while IFS=$'\t' read -r v u msg; do
      [ "$v" = "SYNTAX" ] || continue
      pth=$(awk -F'\t' -v u="$u" '$1==u {print $2" ("$3":"$4")"}' "$OUT/.units.tsv")
      bad "구문 오류: $pth" "$msg"
    done < "$OUT/.classify.tsv"
  else
    ok "구문 검사 통과 — 주장한 완전 파일 ${nfile}개"
  fi
  # ── 타입체크: 의존성이 필요하다 ──
  # **복원과 tsconfig 생성은 tsc 유무와 무관하게 한다.** 예전에는 tsc가 없으면 여기서
  # 곧바로 반환해 실파일 트리도 tsconfig도 남지 않았다 — 그러면 ⓐ 감사 A가 넘겨받는
  # 작업 디렉토리가 「거의 다 된 스크래치 프로젝트」가 아니게 되고(그것이 --keep의 존재
  # 이유다) ⓑ **판정의 전제를 검사할 수 없다**: 검사가 도는 것과 검사가 대상을 보는 것은
  # 다른데, 후자는 tsconfig에 적혀 있고 그 파일이 없으면 확인할 방법이 없다.
  local tsc=""
  command -v tsc >/dev/null 2>&1 && tsc="tsc"
  [ -z "$tsc" ] && [ -x "$OUT/node_modules/.bin/tsc" ] && tsc="$OUT/node_modules/.bin/tsc"

  # 완전 파일만 실제 트리로 옮긴다 (조각은 타입체크 대상이 아니다).
  # **strip-only 모드가 거부한 단위도 옮긴다.** 그 UNSUP은 「이 팩이 틀렸다」가 아니라
  # 「Node의 타입 스트리퍼가 못 지운다」는 뜻이고(enum · namespace · 파라미터 프로퍼티),
  # 위 skip 문구 자체가 "정상 TypeScript일 수 있다 — tsc가 있는 환경에서만 판정된다"고
  # 적고 있다. 그런데 옮기지 않으면 tsc가 있어도 **영영 판정되지 않는다** —
  # NestJS 팩에서는 생성자 주입이 곧 파라미터 프로퍼티라 서비스·컨트롤러가 통째로
  # 타입체크 밖으로 빠졌다 (node-nest 실측 — 미탐). 형식 미지원(JSX·yaml 등)은 그대로 뺀다.
  local dst promoted=0
  while IFS=$'\t' read -r v u msg; do
    case "$v" in
      FILE) ;;
      UNSUP) case "$msg" in *"not supported in strip-only mode"*) promoted=$((promoted+1)) ;; *) continue ;; esac ;;
      *) continue ;;
    esac
    dst=$(awk -F'\t' -v u="$u" '$1==u {print $2}' "$OUT/.units.tsv")
    [ -n "$dst" ] || continue
    mkdir -p "$OUT/$(dirname "$dst")" 2>/dev/null
    cat "$OUT/units/$u" >> "$OUT/$dst"
  done < "$OUT/.classify.tsv"

  # **`@/*`를 `src/`로 못박지 않는다.** 팩마다 배치가 다르다 — nextjs는 `app/`·`stores/`를
  # 프로젝트 루트에 두고 `src/`를 쓰지 않는다. 하나만 두면 그 팩의 정상 import가 전부
  # 미해소가 된다(실측 — 오탐).
  #
  # **`baseUrl`을 쓰지 않는다.** TypeScript 7이 그것을 제거해서
  # `error TS5102: Option 'baseUrl' has been removed`로 **정상 팩이 전부 타입체크 실패**가
  # 된다 (firebase 파일럿 실측). `paths`는 TS 4.4부터 baseUrl 없이 tsconfig 기준으로
  # 해석되므로 5와 7 양쪽에서 같은 뜻이다.
  #
  # `types: []`는 **암묵 전역까지 지운다** — @types/node가 설치돼 있어도 Buffer·process가
  # 「없는 이름」이 되어 정상 팩이 FAIL한다 (aws-serverless 실측 — 오탐 2건).
  # 설치돼 있으면 넣고, 없으면 그때만 비운다.
  # **설치된 @types 를 전부 싣는다.** 하나만 고정하면 팩이 선언한 나머지가 시야 밖이 된다 —
  # `@types/jest` 가 설치돼 있는데 `["node"]` 로 못박혀 있어서 팩이 배송한 테스트 파일이
  # `Cannot find name 'describe'` 로 실패했다 (node-nest 실측 — 오탐). 실프로젝트의
  # tsconfig 는 types 를 생략해 전부 싣는 것이 기본값이고, 여기서 목록을 만드는 이유는
  # 하나도 설치되지 않았을 때 `[]` 로 눌러 두기 위해서다.
  local types='[]' tnames
  tnames=$(ls "$OUT/node_modules/@types" 2>/dev/null | sed 's/^/"/; s/$/"/' | tr '\n' ',' | sed 's/,$//')
  [ -n "$tnames" ] && types="[$tnames]"
  # **데코레이터를 쓰는 팩은 그것을 켠 tsconfig 로만 검사할 수 있다.** TypeScript 5는
  # experimentalDecorators 가 꺼져 있으면 데코레이터를 ES 표준(Stage 3)으로 읽는데,
  # 그 문법에는 **파라미터 데코레이터가 없고** 프로퍼티 데코레이터의 시그니처도 다르다 —
  # 정상 NestJS 팩이 TS1240 으로 통째로 실패한다 (node-nest 실측 — 오탐).
  # 복원된 단위에서 도출한다: 줄 머리의 `@Pascal(` 과 인자 자리의 `(@Pascal(` 둘 다 본다.
  local deco='false'
  if grep -rqE '(^|\()[[:space:]]*@[A-Z][A-Za-z0-9_]*[[:space:]]*[({]' "$OUT/units" 2>/dev/null; then
    deco='true'
  fi
  # **`include`를 하드코딩하지 않는다.** 팩마다 최상위 배치가 다르다 — firebase는 전부
  # `functions/` 아래에 있어서 고정 목록으로는 **tsc가 팩 코드를 한 줄도 보지 않았다**
  # (`TS18003: No inputs were found`가 나도 판정이 초록이었다). 복원된 유닛의 최상위
  # 디렉토리에서 도출한다.
  local inc; inc=$(cut -f2 "$OUT/.units.tsv" 2>/dev/null | grep '/' | cut -d/ -f1 | sort -u \
    | sed 's#^#"#; s#$#/**/*"#' | tr '\n' ',' | sed 's/,$//')
  # **루트에 둔 파일의 확장자를 하나로 못박지 않는다.** `"*.ts"`만 두면 JS 축 팩이 루트에
  # 두는 `main.js`가 tsc 시야 밖이라 **의도한 타입 오류를 심어도 「타입체크 통과」가 난다**
  # (실측 — 미탐). `include`에 있는 것과 검사되는 것은 다르다.
  inc="${inc:+$inc,}\"*.ts\",\"*.js\",\"*.mjs\",\"*.cjs\""
  # **`checkJs`는 팩의 언어로 가른다.** `allowJs`만으로는 `.js`가 파싱되기만 하고 JSDoc
  # 타입은 **하나도 검사되지 않는다** — JS 축 팩의 타입 표준 슬롯(JSDoc + 런타임 스키마
  # 검증)에 검증자가 0이 된다. 그렇다고 전역으로 켜면 TS 팩이 배송하는 설정 조각
  # (`vite.config.js` 류)이 새로 검사 대상이 되어 오탐이 난다. 그래서 **복원 유닛에 TS가
  # 하나도 없을 때만** 켠다 — 그때 이 팩은 JS 팩이다.
  local hasts checkjs='false'
  hasts=$(num "$(cut -f2 "$OUT/.units.tsv" 2>/dev/null | grep -cE '\.(ts|tsx|mts|cts)$' | tr -d ' ')")
  [ "$hasts" -eq 0 ] && checkjs='true'
  # **스텁이 있으면 `noImplicitAny`를 끈다.** 스텁은 정의상 `any`이므로 그것을 소비하는
  # 콜백의 인자가 전부 암묵 any가 된다 — 그 TS7006은 **스텁을 측정한 것이지 팩을 측정한
  # 것이 아니다**(vanilla 실측: 실프로젝트에서는 같은 파일이 무오류로 통과한다).
  # 나머지 strict 항목(strictNullChecks 등)은 그대로 켠다. 생략은 **명시 보고**한다.
  local nia='true'
  if [ -s "$OUT/.stubbed.txt" ]; then nia='false'; fi
  cat > "$OUT/tsconfig.json" <<TSC
{
  "compilerOptions": {
    "target": "ES2022", "module": "ESNext", "moduleResolution": "bundler",
    "strict": true, "noImplicitAny": $nia, "noEmit": true, "skipLibCheck": true,
    "experimentalDecorators": $deco, "emitDecoratorMetadata": $deco,
    "jsx": "preserve", "allowJs": true, "checkJs": $checkjs,
    "paths": { "@/*": ["./src/*", "./*"] },
    "types": $types
  },
  "include": [$inc]
}
TSC
  [ "$checkjs" = "true" ] && ok "JS 팩으로 판정 — checkJs 를 켠다 (JSDoc 타입이 검사된다)"
  [ "$deco" = "true" ] && ok "데코레이터 팩으로 판정 — experimentalDecorators·emitDecoratorMetadata 를 켠다" \
      "끄면 TypeScript 가 데코레이터를 ES 표준으로 읽어 파라미터 데코레이터가 전부 오류가 된다"
  [ "$nia" = "false" ] && warn "noImplicitAny 끔 — 이음매 스텁 $(wc -l < "$OUT/.stubbed.txt" | tr -d ' ')개가 any다" "스텁을 소비하는 콜백 인자의 암묵 any는 팩 결함이 아니다. **이 항목만 미검사**이고 나머지 strict 는 켜져 있다"
  [ "$promoted" -gt 0 ] && ok "구문 미검사 ${promoted}개를 타입체크 대상에 넣는다" \
      "strip-only 모드가 거부한 것은 정상 TypeScript일 수 있다 — tsc 가 판정한다"
  if [ -z "$tsc" ]; then
    skip "tsc 없음 — 타입체크 생략" "오프라인이면 정상이다. 감사 A가 이 작업 디렉토리에서 'npm i -D typescript' 후 tsconfig.json 그대로 돌린다 — 이 항목은 **미검사**이지 통과가 아니다"
    return 0
  fi

  local tout
  if tout=$("$tsc" -p "$OUT/tsconfig.json" 2>&1); then
    ok "타입체크 통과 ($tsc)"
  else
    bad "타입체크 실패" "$(printf '%s' "$tout" | grep -E 'error TS' | head -3 | tr '\n' ';')"
  fi
  return 0
}
