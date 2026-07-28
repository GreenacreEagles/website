import fs from "fs";
import path from "path";

const root = path.resolve("src");
const replacements = [
  // Public page heroes / titles
  [
    /break-words font-display text-4xl font-black uppercase leading-none(?: text-eagles-ink)? sm:text-5xl md:text-6xl lg:text-7xl/g,
    "page-title"
  ],
  [
    /break-words font-display text-4xl font-black uppercase leading-none text-eagles-ink sm:text-5xl md:text-6xl/g,
    "page-title"
  ],
  [
    /font-display text-4xl font-black uppercase leading-none text-eagles-ink md:text-6xl/g,
    "page-title"
  ],
  [
    /font-display text-4xl font-black uppercase leading-none md:text-6xl/g,
    "page-title"
  ],
  [
    /font-display text-4xl font-black uppercase md:text-6xl/g,
    "page-title"
  ],
  [
    /font-display text-4xl font-black uppercase leading-none text-eagles-ink/g,
    "page-title"
  ],
  // Panel / section titles commonly text-3xl
  [
    /font-display text-3xl font-black uppercase leading-none text-eagles-ink/g,
    "panel-title"
  ],
  [
    /font-display text-3xl font-black uppercase leading-none/g,
    "panel-title"
  ],
  [
    /font-display text-3xl font-black uppercase/g,
    "panel-title"
  ],
  // Card-ish 2xl titles that still use display style
  [
    /font-display text-2xl font-black uppercase leading-none/g,
    "card-title"
  ],
  [
    /font-display text-2xl font-black uppercase/g,
    "card-title"
  ]
];

function walk(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (/\.astro$/.test(entry.name)) transform(full);
  }
}

const changed = [];
function transform(file) {
  // Skip shared components already rewritten to use utilities by name
  const rel = path.relative(root, file).replaceAll("\\", "/");
  if (
    [
      "components/SectionHeading.astro",
      "components/AdminPageHeader.astro",
      "components/NewsCard.astro",
      "components/EventCard.astro",
      "components/TeamCard.astro",
      "components/LogoLockup.astro",
      "components/Header.astro",
      "components/FormPanel.astro",
      "components/FundraiserCard.astro"
    ].includes(rel)
  ) {
    return;
  }

  let source = fs.readFileSync(file, "utf8");
  const original = source;
  for (const [pattern, replacement] of replacements) {
    source = source.replace(pattern, replacement);
  }
  if (source !== original) {
    fs.writeFileSync(file, source);
    changed.push(rel);
  }
}

walk(root);
console.log(`Updated ${changed.length} files`);
for (const file of changed) console.log(` - ${file}`);
