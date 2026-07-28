import { chromium } from "playwright";
import path from "path";
import fs from "fs";

const out = path.resolve(".visual-qa/after");
fs.mkdirSync(out, { recursive: true });
const widths = [320, 375, 768, 1024, 1100, 1280, 1440, 1920];
const browser = await chromium.launch({ headless: true });

for (const width of widths) {
  const page = await browser.newPage({ viewport: { width, height: 900 } });
  await page.goto("http://127.0.0.1:4321/", { waitUntil: "domcontentloaded", timeout: 60000 });
  await page.waitForTimeout(400);
  await page.screenshot({ path: path.join(out, `home-${width}.png`), fullPage: false });
  const m = await page.evaluate(() => {
    const h1 = document.querySelector("h1");
    const shell = document.querySelector("section.relative.isolate .section-shell");
    const cols = shell ? [...shell.children] : [];
    let heroOverlap = false;
    if (cols.length >= 2) {
      const a = cols[0].getBoundingClientRect();
      const b = cols[1].getBoundingClientRect();
      const sameRow = Math.abs(a.top - b.top) < 40;
      if (sameRow) heroOverlap = !(a.right <= b.left + 2 || a.left >= b.right - 2);
    }
    const brand = document.querySelector("header a[aria-label]");
    const brandClipped = brand
      ? [...brand.querySelectorAll("span")].some(
          (s) => getComputedStyle(s).whiteSpace === "nowrap" && s.scrollWidth > s.clientWidth + 1
        )
      : false;
    return {
      h1: h1 ? getComputedStyle(h1).fontSize : null,
      h1Overflow: h1 ? h1.scrollWidth > h1.clientWidth + 2 : false,
      h1Text: (h1?.innerText || "").replace(/\s+/g, " ").trim(),
      heroOverlap,
      brandClipped,
      overflow: document.documentElement.scrollWidth > document.documentElement.clientWidth + 1
    };
  });
  console.log(JSON.stringify({ width, ...m }));
  await page.close();
}

await browser.close();
