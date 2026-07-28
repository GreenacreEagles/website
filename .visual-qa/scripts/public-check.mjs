import { chromium } from "playwright";
import fs from "fs";
import path from "path";

const base = "http://127.0.0.1:4321";
const widths = [320, 360, 375, 390, 430, 768, 1024, 1280, 1440, 1920];
const pages = [
  ["home", "/"],
  ["social", "/social/"],
  ["login", "/login/"],
  ["signup", "/signup/"],
  ["reset", "/reset-password/"]
];

const outDir = path.resolve(".visual-qa/public-pass");
fs.mkdirSync(outDir, { recursive: true });

const results = [];
const browser = await chromium.launch({ headless: true });

for (const [name, pagePath] of pages) {
  for (const width of widths) {
    const page = await browser.newPage({ viewport: { width, height: 920 } });
    await page.goto(base + pagePath, { waitUntil: "domcontentloaded", timeout: 60000 });
    await page.waitForTimeout(350);
    await page.screenshot({ path: path.join(outDir, `${name}-${width}.png`), fullPage: false });
    const data = await page.evaluate((pageName) => {
      const de = document.documentElement;
      const overflow = de.scrollWidth > de.clientWidth + 1;
      let fcAlone = false;
      let heroOverlap = false;
      const h1 = document.querySelector("h1");
      if (pageName === "home" && h1) {
        fcAlone = /\nFC\s*$/.test(h1.innerText);
        const shell = document.querySelector("section.relative.isolate .section-shell");
        if (shell && shell.children.length >= 2) {
          const a = shell.children[0].getBoundingClientRect();
          const b = shell.children[1].getBoundingClientRect();
          const sameRow = Math.abs(a.top - b.top) < 40;
          if (sameRow) {
            heroOverlap = !(a.right <= b.left + 2 || a.left >= b.right - 2);
          }
        }
      }
      return { overflow, fcAlone, heroOverlap, title: h1?.innerText ?? null };
    }, name);

    results.push({ page: name, width, ...data });
    console.log(
      JSON.stringify({
        page: name,
        width,
        overflow: data.overflow,
        fcAlone: data.fcAlone,
        heroOverlap: data.heroOverlap
      })
    );
    await page.close();
  }
}

await browser.close();
fs.writeFileSync(path.resolve(".visual-qa/public-pass/results.json"), JSON.stringify(results, null, 2));
console.log("wrote", results.length, "checks");
