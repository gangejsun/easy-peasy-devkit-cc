// skills/ui-ux-design/scripts/ui-probe.browser.mjs
//
// ui-probe.sh 의 실행부. 브라우저를 한 번 띄워 **정찰과 증거를 같은 패스에서** 모으고
// JSON 한 덩어리를 stdout 으로 낸다. 사람이 읽는 서식·판정·종료 코드는 호출자(bash)가 만든다.
//
// 직접 부르지 않는다 — 계약(--help · 0/1/2 · 3상태)은 ui-probe.sh 가 소유한다.
//
// 인자: argv[2] = 설정 JSON (ui-probe.sh 가 만든다)
// 종료 코드: 0 = 수집 성공(결함 유무와 무관) · 2 = 판정 불가(브라우저 부재·접속 실패)

import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const CFG = JSON.parse(process.argv[2] || '{}');

const VIEWPORTS = {
  mobile: { width: 390, height: 844, isMobile: true },
  tablet: { width: 768, height: 1024, isMobile: true },
  desktop: { width: 1440, height: 900, isMobile: false },
};

function bail(reason, hint) {
  process.stdout.write(JSON.stringify({ undecidable: reason, hint: hint || null }) + '\n');
  process.exit(2);
}

// ── playwright 해석 ──────────────────────────────────────────────────
// ESM import 는 **이 파일 기준**으로 해석된다. 이 파일은 플러그인 캐시 안에 살고
// node_modules 가 없다. 소비자 프로젝트의 설치본을 써야 하므로 cwd 기준으로 해석한다.
async function loadChromium() {
  const req = createRequire(path.join(process.cwd(), 'ui-probe.resolve.cjs'));
  const errs = [];
  for (const name of ['playwright', 'playwright-core', '@playwright/test']) {
    try {
      const mod = await import(pathToFileURL(req.resolve(name)).href);
      const chromium = (mod.chromium || mod.default?.chromium);
      if (chromium) return { chromium, from: name };
    } catch (e) { errs.push(`${name}: ${e.code || e.message}`); }
  }
  bail(
    'playwright 를 찾을 수 없습니다',
    `이 프로젝트에 설치하세요: npm i -D playwright && npx playwright install chromium\n(확인한 경로: ${errs.join(' / ')})`
  );
}

// ── 페이지 안에서 도는 수집기 ────────────────────────────────────────
// 문자열로 넘겨 page.evaluate 로 실행한다. 여기서 참조하는 것은 브라우저 전역뿐이다.
function inPageCollect(opts) {
  // 인벤토리 상한. 기본을 작게 두는 것이 요점이다 — 이 출력은 모델 컨텍스트로 들어간다.
  // 선택자를 실제로 찾아야 할 때만 --recon 으로 넓힌다.
  const CAP = opts.recon ? 40 : 8;
  const vis = (el) => {
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) return false;
    const s = getComputedStyle(el);
    return s.visibility !== 'hidden' && s.display !== 'none' && s.opacity !== '0';
  };
  const name = (el) =>
    (el.getAttribute('aria-label') ||
      el.getAttribute('placeholder') ||
      (el.innerText || '').trim().split('\n')[0] ||
      el.getAttribute('name') ||
      el.getAttribute('title') ||
      el.value ||
      '').slice(0, 60);
  const hint = (el) => {
    if (el.getAttribute('data-testid')) return `[data-testid="${el.getAttribute('data-testid')}"]`;
    if (el.id) return `#${el.id}`;
    if (el.getAttribute('aria-label')) return `[aria-label="${el.getAttribute('aria-label')}"]`;
    const t = name(el);
    return t ? `text=${t}` : el.tagName.toLowerCase();
  };

  // ── 정찰: 상호작용 요소 인벤토리 ──
  const grab = (sel) => Array.from(document.querySelectorAll(sel)).filter(vis);
  const buttons = grab('button, [role="button"], input[type="submit"], input[type="button"]');
  const links = grab('a[href]');
  const inputs = grab('input:not([type="hidden"]):not([type="submit"]):not([type="button"]), textarea, select');
  const pack = (els) => ({
    total: els.length,
    items: els.slice(0, CAP).map((el) => ({ name: name(el), hint: hint(el) })),
  });
  const recon = { buttons: pack(buttons), links: pack(links), inputs: pack(inputs) };

  if (!opts.quality) return { recon, quality: null };

  // ── 품질 실측 (전부 WARN 축이다 — 오탐이 차단으로 번지지 않게 한다) ──
  const q = {};

  // 1) 터치 타겟 44px — 모바일 뷰포트에서만 의미가 있다.
  //    문단 속 인라인 링크는 구조적으로 44px 가 될 수 없다 → display:inline 인 a 는 제외한다.
  if (opts.isMobile) {
    const targets = [...buttons, ...links, ...inputs].filter((el) => {
      if (el.disabled || el.getAttribute('aria-disabled') === 'true') return false;
      if (el.tagName === 'A' && getComputedStyle(el).display === 'inline') return false;
      return true;
    });
    const bad = targets
      .map((el) => ({ el, r: el.getBoundingClientRect() }))
      .filter(({ r }) => r.width < 44 || r.height < 44)
      .map(({ el, r }) => ({ name: name(el), hint: hint(el), w: Math.round(r.width), h: Math.round(r.height) }));
    q.touchTargets = { checked: targets.length, violations: bad.slice(0, 5), total: bad.length };
  }

  // 2) 본문 16px — 개별 요소가 아니라 **중앙값**을 본다. 캡션·각주 하나로 경고를 띄우지 않는다.
  const paras = grab('p, li').filter((el) => (el.innerText || '').trim().length > 20);
  if (paras.length) {
    const sizes = paras.map((el) => parseFloat(getComputedStyle(el).fontSize)).sort((a, b) => a - b);
    const median = sizes[Math.floor(sizes.length / 2)];
    q.bodyFontSize = { median: Math.round(median * 10) / 10, sampled: sizes.length, ok: median >= 16 };
  }

  // 3) interactive 요소의 cursor:pointer — 비활성 요소는 제외한다(not-allowed 가 정상이다).
  const clickable = [...buttons, ...links].filter(
    (el) => !el.disabled && el.getAttribute('aria-disabled') !== 'true'
  );
  const noPointer = clickable
    .filter((el) => getComputedStyle(el).cursor !== 'pointer')
    .map((el) => ({ name: name(el), hint: hint(el), cursor: getComputedStyle(el).cursor }));
  q.cursor = { checked: clickable.length, violations: noPointer.slice(0, 5), total: noPointer.length };

  // 4) 대비율 4.5:1 — 오탐 원천을 먼저 제거한다.
  //    배경 이미지·그라디언트가 조상에 있으면 계산값이 실제 배경이 아니므로 **건너뛴다.**
  const lum = (rgb) => {
    const c = rgb.map((v) => {
      const s = v / 255;
      return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
    });
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
  };
  const parse = (s) => {
    const m = (s || '').match(/rgba?\(([^)]+)\)/);
    if (!m) return null;
    const p = m[1].split(',').map((x) => parseFloat(x));
    return { rgb: [p[0], p[1], p[2]], a: p.length > 3 ? p[3] : 1 };
  };
  const bgOf = (el) => {
    let cur = el;
    while (cur && cur !== document.documentElement.parentNode) {
      const s = getComputedStyle(cur);
      if (s.backgroundImage && s.backgroundImage !== 'none') return null; // 판정 불가
      const b = parse(s.backgroundColor);
      if (b && b.a > 0.95) return b.rgb;
      cur = cur.parentElement;
    }
    return [255, 255, 255];
  };
  const texts = Array.from(document.querySelectorAll('p, li, span, a, h1, h2, h3, h4, h5, h6, button, label, td'))
    .filter(vis)
    .filter((el) => Array.from(el.childNodes).some((n) => n.nodeType === 3 && n.textContent.trim().length > 1));
  const cbad = [];
  let cchecked = 0;
  for (const el of texts.slice(0, 400)) {
    const s = getComputedStyle(el);
    const fg = parse(s.color);
    const bg = bgOf(el);
    if (!fg || !bg || fg.a < 0.95) continue;
    cchecked++;
    const size = parseFloat(s.fontSize);
    const bold = parseInt(s.fontWeight, 10) >= 700;
    const need = size >= 24 || (size >= 18.66 && bold) ? 3 : 4.5;
    const l1 = lum(fg.rgb), l2 = lum(bg);
    const ratio = (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
    if (ratio < need) {
      cbad.push({ name: name(el), hint: hint(el), ratio: Math.round(ratio * 100) / 100, need });
    }
  }
  q.contrast = { checked: cchecked, violations: cbad.slice(0, 5), total: cbad.length };

  return { recon, quality: q };
}

// ── 실행 ─────────────────────────────────────────────────────────────
const { chromium, from } = await loadChromium();

let browser;
try {
  browser = await chromium.launch({ headless: true });
} catch (e) {
  bail(
    '크로미움을 실행할 수 없습니다',
    `브라우저 바이너리를 설치하세요: npx playwright install chromium\n(${e.message.split('\n')[0]})`
  );
}

const timeout = (CFG.timeout || 15) * 1000;
const ignore = CFG.ignore ? new RegExp(CFG.ignore) : null;
const result = {
  undecidable: null,
  url: CFG.url,
  playwrightFrom: from,
  wait: { strategy: null, warning: null },
  runtime: { consoleErrors: [], pageErrors: [], failedRequests: [] },
  quality: null,
  recon: null,
  screenshots: [],
  reducedMotion: null,
};

// 같은 결함이 뷰포트마다 반복 보고되지 않게 텍스트로 접는다.
const seen = new Set();
const push = (bucket, key, obj) => {
  if (seen.has(key)) return;
  seen.add(key);
  result.runtime[bucket].push(obj);
};

async function visit(vpName, opts = {}) {
  const vp = VIEWPORTS[vpName];
  const ctx = await browser.newContext({
    viewport: { width: vp.width, height: vp.height },
    isMobile: false, // deviceScaleFactor/touch 에뮬레이션은 폰트 실측을 왜곡한다
    ...(opts.reducedMotion ? { reducedMotion: 'reduce' } : {}),
  });
  const page = await ctx.newPage();

  page.on('console', (m) => {
    if (m.type() !== 'error') return;
    const t = m.text();
    if (ignore && ignore.test(t)) return;
    // 리소스 적재 실패는 브라우저가 콘솔에도 찍는다. failedRequests 가 URL·상태까지
    // 담아 같은 사실을 더 정확히 보고하므로 여기서 두 번 세지 않는다.
    if (/^Failed to load resource/.test(t)) return;
    push('consoleErrors', 'c:' + t, { text: t.slice(0, 300), viewport: vpName });
  });
  page.on('pageerror', (e) => {
    const t = e.message || String(e);
    push('pageErrors', 'p:' + t, { text: t.slice(0, 300), viewport: vpName });
  });
  page.on('response', (r) => {
    const s = r.status();
    if (s < 400) return;
    if (ignore && ignore.test(r.url())) return;
    if (/favicon\.ico(\?|$)/.test(r.url())) return;
    push('failedRequests', 'r:' + r.url(), { url: r.url().slice(0, 200), status: s, viewport: vpName });
  });
  page.on('requestfailed', (r) => {
    const u = r.url();
    if (ignore && ignore.test(u)) return;
    if (/favicon\.ico(\?|$)/.test(u)) return;
    push('failedRequests', 'r:' + u, {
      url: u.slice(0, 200),
      status: r.failure()?.errorText || 'failed',
      viewport: vpName,
    });
  });

  try {
    await page.goto(CFG.url, { waitUntil: 'load', timeout });
  } catch (e) {
    await ctx.close();
    throw new Error(`접속 실패 — ${e.message.split('\n')[0]}`);
  }

  // ── 대기 규율 ──
  // 가시성 기반이 1순위다. networkidle 은 Playwright 가 비권장하는 API이고
  // 폴링·SSE·웹소켓 앱에서는 영원히 안정되지 않는다. 고정 대기는 쓰지 않는다.
  if (CFG.ready) {
    await page.locator(CFG.ready).first().waitFor({ state: 'visible', timeout });
    result.wait.strategy = `visible: ${CFG.ready}`;
  } else {
    // --ready 가 없을 때의 대리: 본문에 내용이 생길 때까지. SPA 의 빈 #root 를 넘긴다.
    try {
      await page.waitForFunction(
        () => document.body && ((document.body.innerText || '').trim().length > 0 ||
          document.body.querySelector('img, svg, canvas, video')),
        { timeout }
      );
    } catch { /* 내용이 끝내 안 생겨도 아래에서 그대로 관측한다 */ }
    result.wait.strategy = 'load + 본문 내용 출현';
    result.wait.warning = '--ready <selector> 를 주면 훨씬 신뢰할 수 있다 — 지금은 대리 대기다';
  }

  const collected = await page.evaluate(
    `(${inPageCollect.toString()})(${JSON.stringify({ quality: CFG.quality, recon: CFG.recon, isMobile: vp.isMobile })})`
  );

  if (opts.reducedMotion) {
    result.reducedMotion = await page.evaluate(() =>
      document.getAnimations()
        .filter((a) => a.playState === 'running' && (a.effect?.getTiming?.().duration || 0) > 0).length
    );
  } else {
    if (!result.recon) result.recon = collected.recon;
    if (collected.quality) result.quality = { ...(result.quality || {}), ...collected.quality };

    if (CFG.out) {
      const p = path.join(CFG.out, `${vpName}.png`);
      await page.screenshot({ path: p, fullPage: true });
      result.screenshots.push({ viewport: vpName, path: p });
    }
  }

  await ctx.close();
}

try {
  for (const v of CFG.viewports) {
    if (!VIEWPORTS[v]) continue;
    await visit(v);
  }
  // prefers-reduced-motion 은 별도 컨텍스트가 필요하다 — 데스크톱에서 한 번만 본다.
  if (CFG.quality) await visit('desktop', { reducedMotion: true });
} catch (e) {
  await browser.close();
  bail(e.message, null);
}

await browser.close();
process.stdout.write(JSON.stringify(result) + '\n');
