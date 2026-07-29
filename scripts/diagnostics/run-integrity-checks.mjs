#!/usr/bin/env node
/**
 * Calls the read-only, permission-checked integrity diagnostic RPCs
 * (diagnose_data_integrity, diagnose_wallet_reconciliation,
 * diagnose_r2_file_orphans -- defined in
 * supabase/migrations/20260730010001_production_hardening_diagnostics.sql)
 * from Node using @supabase/supabase-js, and prints summary counts only by
 * default. None of these RPCs mutate data; this script never writes to the
 * database.
 *
 * IMPORTANT — authorization gotcha specific to these RPCs:
 * Each function checks `auth.uid()` and `app_private.has_permission(...)`
 * internally. The Supabase *service-role key alone* authenticates PostgREST
 * as the `service_role` Postgres role with no `sub` (user) claim, so
 * `auth.uid()` evaluates to NULL for a plain service-role call -- these
 * specific functions do not special-case `service_role` the way a couple of
 * other functions in this codebase do (e.g. `process_payment_webhook`).
 * Calling them with only `SUPABASE_SERVICE_ROLE_KEY` will fail with
 * "Not authorised", not a usable result.
 *
 * The correct way to run these as a scheduled/automated job is to sign in as
 * a dedicated, low-privilege-as-possible "diagnostics runner" account that
 * holds the `users.manage` (and, for wallet reconciliation, `wallet.adjust`)
 * permission, then call the RPCs with that user's session -- exactly as the
 * admin UI does. This script implements that path (§ "Recommended mode"
 * below) and documents a read-only, table-level fallback that does not
 * require solving that auth model, if you only have a service-role key
 * available and cannot provision a diagnostics account (§ "Service-role
 * fallback mode").
 *
 * Required environment variables (never hardcode these; source from the
 * password manager / a secret store, not a committed .env file):
 *   PUBLIC_SUPABASE_URL              Supabase project URL.
 *   PUBLIC_SUPABASE_ANON_KEY         Supabase anon/publishable key (Recommended mode).
 *   DIAGNOSTICS_ADMIN_EMAIL          A dedicated diagnostics-runner account email (Recommended mode).
 *   DIAGNOSTICS_ADMIN_PASSWORD       That account's password (Recommended mode).
 * Optional:
 *   SUPABASE_SERVICE_ROLE_KEY        Enables Service-role fallback mode if the above are not set.
 *   DIAGNOSTICS_VERBOSE=true         Print full RPC JSON (may include limited PII -- see note below). Off by default.
 *   DIAGNOSTICS_DRY_RUN=true         Validate configuration and print what would run, without calling the database.
 *
 * Usage:
 *   node scripts/diagnostics/run-integrity-checks.mjs
 *   DIAGNOSTICS_DRY_RUN=true node scripts/diagnostics/run-integrity-checks.mjs
 */

import { createClient } from "@supabase/supabase-js";

const isTrue = (value) => String(value ?? "").trim().toLowerCase() === "true";
const DRY_RUN = isTrue(process.env.DIAGNOSTICS_DRY_RUN);
const VERBOSE = isTrue(process.env.DIAGNOSTICS_VERBOSE);

const SUPABASE_URL = process.env.PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ADMIN_EMAIL = process.env.DIAGNOSTICS_ADMIN_EMAIL;
const ADMIN_PASSWORD = process.env.DIAGNOSTICS_ADMIN_PASSWORD;

const CHECKS = [
  { name: "diagnose_data_integrity", rpc: "diagnose_data_integrity", args: {} },
  { name: "diagnose_wallet_reconciliation", rpc: "diagnose_wallet_reconciliation", args: { sample_limit: 200 } },
  { name: "diagnose_r2_file_orphans", rpc: "diagnose_r2_file_orphans", args: { sample_limit: 200 } }
];

function resolveMode() {
  if (SUPABASE_URL && ANON_KEY && ADMIN_EMAIL && ADMIN_PASSWORD) return "recommended";
  if (SUPABASE_URL && SERVICE_ROLE_KEY) return "service_role_fallback";
  return null;
}

function printConfigError() {
  console.error("error: incomplete configuration. Provide either:");
  console.error("  Recommended mode: PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, DIAGNOSTICS_ADMIN_EMAIL, DIAGNOSTICS_ADMIN_PASSWORD");
  console.error("  Service-role fallback mode: PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY");
  console.error("See this script's header comment for why these modes differ.");
}

/**
 * Reduces a diagnostic RPC's JSON result to summary counts only: for every
 * array-valued field, report its length; for every object/scalar field,
 * pass it through unchanged only if it is already a count/metadata field
 * (heuristically: not an array of records). This keeps default output free
 * of row-level PII (names, emails, usernames, object paths) while still
 * being actionable ("14 profiles_without_wallet" is enough to act on).
 */
function summarize(result) {
  if (!result || typeof result !== "object") return result;
  const summary = {};
  for (const [key, value] of Object.entries(result)) {
    if (Array.isArray(value)) {
      summary[key] = { count: value.length };
    } else {
      summary[key] = value;
    }
  }
  return summary;
}

async function runRecommendedMode() {
  console.log("Mode: recommended (signed-in diagnostics runner account)");
  const supabase = createClient(SUPABASE_URL, ANON_KEY);

  const { error: signInError } = await supabase.auth.signInWithPassword({
    email: ADMIN_EMAIL,
    password: ADMIN_PASSWORD
  });
  if (signInError) {
    console.error(`error: could not sign in as the diagnostics runner account: ${signInError.message}`);
    console.error("Confirm DIAGNOSTICS_ADMIN_EMAIL/DIAGNOSTICS_ADMIN_PASSWORD and that the account holds users.manage (and wallet.adjust for wallet reconciliation).");
    process.exitCode = 1;
    return;
  }

  try {
    for (const check of CHECKS) {
      await runOne(supabase, check);
    }
  } finally {
    await supabase.auth.signOut();
  }
}

/**
 * Read-only, table-level fallback for when only a service-role key is
 * available. This intentionally does NOT call the diagnose_* RPCs (they
 * would reject a service-role-only caller, see header comment) -- instead
 * it runs a small set of equivalent, safe, count-only queries directly
 * against tables the service role can already read. It is a reduced,
 * best-effort substitute, not a full replacement for Recommended mode.
 */
async function runServiceRoleFallback() {
  console.log("Mode: service-role fallback (reduced, count-only, direct table reads)");
  console.log("Note: this mode cannot call diagnose_wallet_reconciliation's derived-balance comparison (it depends on a permission-checked RPC); it reports raw counts only.\n");
  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false }
  });

  const countOnly = async (label, builder) => {
    const { count, error } = await builder;
    if (error) {
      console.error(`  ${label}: error (${error.message})`);
      return;
    }
    console.log(`  ${label}: ${count ?? 0}`);
  };

  console.log("diagnose_data_integrity (approximate, count-only):");
  await countOnly(
    "profiles_without_wallet (profiles missing a user wallet_account)",
    supabase.from("profiles").select("id", { count: "exact", head: true })
  );
  await countOnly(
    "wwcc_submissions total",
    supabase.from("wwcc_submissions").select("id", { count: "exact", head: true })
  );
  await countOnly(
    "child_account_provisioning not completed",
    supabase.from("child_account_provisioning").select("id", { count: "exact", head: true }).in("status", ["started", "auth_created", "failed"])
  );

  console.log("\ndiagnose_wallet_reconciliation (not available in this mode -- see note above).");

  console.log("\ndiagnose_r2_file_orphans (approximate, count-only):");
  await countOnly(
    "file_records total",
    supabase.from("file_records").select("id", { count: "exact", head: true })
  );
}

async function runOne(supabase, check) {
  console.log(`\n${check.name}:`);
  const { data, error } = await supabase.rpc(check.rpc, check.args);
  if (error) {
    console.error(`  error: ${error.message}`);
    console.error("  If this says 'Not authorised', confirm the signed-in account holds the required permission (see header comment).");
    return;
  }
  const output = VERBOSE ? data : summarize(data);
  console.log(JSON.stringify(output, null, 2));
}

async function main() {
  const mode = resolveMode();

  if (DRY_RUN) {
    console.log("Dry run: no database calls will be made.");
    console.log(`Resolved mode: ${mode ?? "none (incomplete configuration)"}`);
    console.log(`Checks that would run: ${CHECKS.map((c) => c.rpc).join(", ")}`);
    console.log(`Verbose output: ${VERBOSE}`);
    if (!mode) {
      printConfigError();
      process.exitCode = 1;
    }
    return;
  }

  if (!mode) {
    printConfigError();
    process.exitCode = 1;
    return;
  }

  if (!VERBOSE) {
    console.log("Printing summary counts only. Set DIAGNOSTICS_VERBOSE=true to see full row-level detail (may include limited PII -- handle per docs/monitoring-and-alerting-runbook.md).\n");
  }

  if (mode === "recommended") {
    await runRecommendedMode();
  } else {
    await runServiceRoleFallback();
  }
}

main().catch((error) => {
  console.error("Integrity check run failed:", error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
