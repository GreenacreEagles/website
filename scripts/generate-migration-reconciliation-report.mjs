import { readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const root = process.cwd();
const migrationDir = path.join(root, "supabase", "migrations");
const remoteVersions = new Set([
  "20260721130000","20260721134500","20260721143000","20260721150000","20260721153000",
  "20260721154500","20260721155000","20260721155500","20260721235654","20260722034732",
  "20260722112430","20260726124106","20260726130513","20260726131535","20260726131614",
  "20260726131859","20260726132109","20260726133228","20260726133822","20260726135629",
  "20260726135955","20260726141535","20260726144708","20260726151031","20260726160340",
  "20260726161347","20260727063619","20260727075752","20260727075901","20260727080031",
  "20260727080453","20260727140928"
]);

const equivalent = new Map(Object.entries({
  "20260726125756":"20260726130513", "20260726131544":"20260726131614",
  "20260726131813":"20260726131859", "20260726132047":"20260726132109",
  "20260726133034":"20260726133228", "20260726133724":"20260726133822",
  "20260726135934":"20260726135955", "20260726141508":"20260726141535",
  "20260726144455":"20260726144708", "20260727062245":"20260727063619",
  "20260727071413":"20260727075752", "20260727075829":"20260727075901",
  "20260727075959":"20260727080031", "20260727081500":"20260727080453"
}));

const classifications = {
  "20260727085028": ["partially applied manually", "Role/permission structures exist, but member_compliance and its dependent compliance statements are absent."],
  "20260727110450": ["partially applied manually", "Location text support is present in places, but venues and canteen_venues still exist; destructive drops were not applied."],
  "20260727111513": ["partially applied manually", "The age_groups table still exists, so the two-statement simplification was not completed."],
  "20260728021848": ["not applied", "wwcc_submissions, its functions, policies, indexes and trigger are absent."],
  "20260728120000": ["not applied", "Its volunteer/family/team-board corrective objects are absent and it depends on the unapplied WWCC migration."],
  "20260726131056": ["unable to determine safely", "Production has event_ticketing under 20260726131535, but normalized SQL differs."],
  "20260726135312": ["unable to determine safely", "Production has secure_sponsor_management under 20260726135629, but normalized SQL differs."],
  "20260727090000": ["unable to determine safely", "Production has simplify_canteen_operations under 20260726151031, but normalized SQL differs."]
};

function splitSql(sql) {
  const out = [];
  let start = 0, quote = null, dollar = null, line = false, block = false;
  for (let i = 0; i < sql.length; i++) {
    const c = sql[i], n = sql[i + 1];
    if (line) { if (c === "\n") line = false; continue; }
    if (block) { if (c === "*" && n === "/") { block = false; i++; } continue; }
    if (!quote && !dollar && c === "-" && n === "-") { line = true; i++; continue; }
    if (!quote && !dollar && c === "/" && n === "*") { block = true; i++; continue; }
    if (!quote && c === "$") {
      const match = sql.slice(i).match(/^\$[A-Za-z0-9_]*\$/);
      if (match && (!dollar || match[0] === dollar)) { dollar = dollar ? null : match[0]; i += match[0].length - 1; continue; }
    }
    if (!dollar && (c === "'" || c === '"')) {
      if (quote === c && n === c) { i++; continue; }
      quote = quote === c ? null : (quote ?? c);
      continue;
    }
    if (!quote && !dollar && c === ";") {
      const statement = sql.slice(start, i + 1).trim();
      if (statement) out.push(statement);
      start = i + 1;
    }
  }
  const tail = sql.slice(start).trim();
  if (tail) out.push(tail);
  return out;
}

const files = (await readdir(migrationDir)).filter((file) => /^\d{14}_.+\.sql$/.test(file)).sort();
const localOnly = files.filter((file) => !remoteVersions.has(file.slice(0, 14)));
const lines = [
  "# Supabase migration reconciliation — 2026-07-29",
  "",
  "No production DDL, data changes, or migration-history repairs were made during this audit.",
  "",
  "## Decision summary",
  "",
  "- 14 local timestamps contain SQL equivalent to migrations recorded in production under later timestamps. These are the only repair candidates, after CLI authentication.",
  "- 13 early portal migrations have extensive matching catalog objects, but data statements, grants, and function bodies cannot all be proven from catalog presence alone; they remain **unable to determine safely**.",
  "- Three alternate-timestamp migrations differ from the recorded production SQL and remain **unable to determine safely**.",
  "- Three later migrations are **partially applied manually**.",
  "- The WWCC and member-portal workflow migrations are **not applied**.",
  "- Later dependency chain: `20260727085028` → `20260728021848` → `20260728120000`.",
  "",
  "## Statement-by-statement comparison",
  "",
  "Each statement below is listed in local execution order. “Matching alternate migration” means the complete normalized local SQL matches the recorded production migration; therefore every listed statement is present and must not be rerun.",
  ""
];

for (const file of localOnly) {
  const version = file.slice(0, 14);
  const sql = await readFile(path.join(migrationDir, file), "utf8");
  const statements = splitSql(sql);
  let status, evidence;
  if (equivalent.has(version)) {
    status = "fully applied manually";
    evidence = `Complete normalized SQL matches recorded production migration ${equivalent.get(version)}.`;
  } else if (classifications[version]) {
    [status, evidence] = classifications[version];
  } else {
    status = "unable to determine safely";
    evidence = "Expected tables, functions, policies, triggers and indexes are substantially present, but catalog presence cannot prove every DML, grant, function body and later superseding change.";
  }
  lines.push(`### ${file.replace(".sql", "")}`, "", `Classification: **${status}**. ${evidence}`, "");
  statements.forEach((statement, index) => {
    const head = statement.replace(/--.*$/gm, "").replace(/\s+/g, " ").trim().slice(0, 180);
    lines.push(`${index + 1}. \`${head.replaceAll("`", "\\`")}${head.length === 180 ? "…" : ""}\` — **${status}** (${evidence})`);
  });
  lines.push("");
}

lines.push(
  "## Production observations",
  "",
  "- Present: the expected legacy team, family, wallet, canteen, merchandise, notification and content tables; their sampled policies, triggers and indexes are also present.",
  "- Absent: `member_compliance`, `wwcc_submissions`, WWCC functions/policies/indexes/trigger, and the new member-portal volunteer/family corrective functions.",
  "- Still present: `venues`, `canteen_venues`, and `age_groups`; therefore the destructive simplification migrations were not fully applied.",
  "- Constraint drift: `wallet_qr_tokens` uses a `(wallet_account_id, status)` unique constraint rather than the local wallet-only constraint. `voucher_templates.code` is not backed by the expected named unique constraint.",
  "",
  "## Safe next actions",
  "",
  "1. Authenticate the Supabase CLI.",
  "2. Repair only the 14 proven equivalent local timestamps with `supabase migration repair <timestamp> --status applied`; do not rerun their SQL.",
  "3. Diff the three non-equivalent alternate migrations against the recorded production bodies before deciding whether a corrective migration is needed.",
  "4. Create forward-only corrective migrations for the missing compliance/WWCC/member-portal statements; do not mark those source migrations applied first.",
  "5. Re-run migration history and RLS/database tests before deployment.",
  ""
);

await writeFile(path.join(root, "docs", "supabase-migration-reconciliation-20260729.md"), lines.join("\n"), "utf8");
