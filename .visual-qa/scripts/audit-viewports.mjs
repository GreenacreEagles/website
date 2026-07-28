import { chromium } from "playwright";
import fs from "fs";
import path from "path";

const phase = process.argv[2] === "after" ? "after" : "before";
const base = process.env.VISUAL_BASE_URL || "http://127.0.0.1:4321";
const outDir = path.resolve(`.visual-qa/${phase}`);
const widths = [320, 360, 375, 390, 430, 768, 1024, 1100, 1280, 1366, 1440, 1920];
const pages = [
  { name: "home", path: "/" },
  { name: "news", path: "/news/" },
  { name: "events", path: "/events/" },
  { name: "teams", path: "/teams/" },
  { name: "login", path: "/login/" }
];

fs.mkdirSync(outDir, { recursive: true });

const findings = [];
const browser = await chromium.launch({ headless: true });

for (const pageDef of pages) {
  for (const width of widths) {
    const page = await browser.newPage({ viewport: { width, height: 900 } });
    const url = base + pageDef.path;
    try {
      await page.goto(url, { waitUntil: "domcontentloaded", timeout: 60000 });
      await page.waitForTimeout(500);
      const shot = path.join(outDir, `${pageDef.name}-${width}.png`);
      await page.screenshot({ path: shot, fullPage: false });

      const metrics = await page.evaluate(() => {
        const doc = document.documentElement;
        const body = document.body;
        const scrollWidth = Math.max(doc.scrollWidth, body.scrollWidth);
        const clientWidth = doc.clientWidth;
        const brand = document.querySelector("header a[aria-label]");
        const h1 = document.querySelector("h1");
        const heroShell = document.querySelector("section.relative.isolate .section-shell");
        const heroCols = heroShell ? [...heroShell.children] : [];
        const overflowing = [];
        document.querySelectorAll("h1,h2,h3,a,button,p,span").forEach((el) => {
          const style = getComputedStyle(el);
          if (
            (style.overflow === "hidden" || style.textOverflow === "ellipsis" || style.whiteSpace === "nowrap") &&
            el.scrollWidth > el.clientWidth + 1
          ) {
            overflowing.push({
              tag: el.tagName,
              text: (el.textContent || "").trim().slice(0, 80),
              scrollWidth: el.scrollWidth,
              clientWidth: el.clientWidth,
              whiteSpace: style.whiteSpace
            });
          }
        });

        let heroOverlap = false;
        if (heroCols.length >= 2) {
          const a = heroCols[0].getBoundingClientRect();
          const b = heroCols[1].getBoundingClientRect();
          const sameRow = Math.abs(a.top - b.top) < 40;
          if (sameRow) {
            heroOverlap = !(a.right <= b.left + 2 || a.left >= b.right - 2);
          }
        }

        const h1Style = h1 ? getComputedStyle(h1) : null;
        return {
          scrollWidth,
          clientWidth,
          horizontalOverflow: scrollWidth > clientWidth + 1,
          brandText: brand?.innerText?.replace(/\s+/g, " ").trim() || "",
          brandClipped: brand ? brand.scrollWidth > brand.clientWidth + 2 : false,
          brandNowrapOverflow: (() => {
            if (!brand) return false;
            const spans = [...brand.querySelectorAll("span")];
            return spans.some((span) => {
              const style = getComputedStyle(span);
              return style.whiteSpace === "nowrap" && span.scrollWidth > span.clientWidth + 1;
            });
          })(),
          h1Text: (h1?.textContent || "").trim().replace(/\s+/g, " ").slice(0, 120),
          h1FontSize: h1Style?.fontSize || null,
          h1LineHeight: h1Style?.lineHeight || null,
          h1Overflow: h1 ? h1.scrollWidth > h1.clientWidth + 2 : false,
          heroOverlap,
          overflowing: overflowing.slice(0, 15)
        };
      });

      findings.push({ page: pageDef.name, width, ...metrics, shot });
      console.log(
        JSON.stringify({
          page: pageDef.name,
          width,
          overflow: metrics.horizontalOverflow,
          brandClipped: metrics.brandClipped || metrics.brandNowrapOverflow,
          heroOverlap: metrics.heroOverlap,
          h1: metrics.h1FontSize,
          h1Overflow: metrics.h1Overflow,
          clippedCount: metrics.overflowing.length
        })
      );
    } catch (err) {
      findings.push({ page: pageDef.name, width, error: String(err) });
      console.error(pageDef.name, width, err.message);
    } finally {
      await page.close();
    }
  }
}

await browser.close();
fs.writeFileSync(path.resolve(`.visual-qa/${phase}-findings.json`), JSON.stringify(findings, null, 2));
console.log(`Wrote ${findings.length} findings to .visual-qa/${phase}-findings.json`);
