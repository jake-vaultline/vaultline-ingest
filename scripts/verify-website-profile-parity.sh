#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/vaultline-website" >&2
  exit 2
fi

website_root="$1"
expected_website_commit="c359dc7edda61e664056afa250176c32f31d4acc"
actual_website_commit="$(git -C "$website_root" rev-parse HEAD)"
if [[ "$actual_website_commit" != "$expected_website_commit" ]]; then
  echo "website checkout must be exact ${expected_website_commit}; got ${actual_website_commit}" >&2
  exit 1
fi
if [[ -n "$(git -C "$website_root" status --porcelain)" ]]; then
  echo "website checkout must be clean at the exact generator commit" >&2
  exit 1
fi
fixture_root="$(pwd)/parity-fixtures"
fixture_dir="$fixture_root/$(uuidgen | tr '[:upper:]' '[:lower:]')"
fixture_alias="$fixture_root/current"
if [[ -e "$fixture_alias" || -L "$fixture_alias" ]]; then
  echo "an existing parity fixture is present; refusing to clobber it" >&2
  exit 1
fi
mkdir -p "$fixture_dir"
ln -s "$fixture_dir" "$fixture_alias"
trap 'rm -f "$fixture_alias"; rm -rf "$fixture_dir"' EXIT

valid_profile="$fixture_dir/website-profile.json"
invalid_profile="$fixture_dir/website-invalid-profile.json"
node - "$website_root" "$valid_profile" "$invalid_profile" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const [websiteRoot, validPath, invalidPath] = process.argv.slice(2);
const { buildConfiguredDelivery } = require(path.join(websiteRoot, "api", "_ingest-config.js"));
const request = {
  email: "jordan@example.test", teamName: "Northstar", confirmed: true,
  permission_to_follow_up: "yes", website: "", scan: { sampleSize: 120, consistency: 0.84 },
  fields: ["shootDate", "project", "jobNumber", "camera", "reel", "notes"],
  jobNameTemplate: "{date:yyMMdd}_{jobNumber}_{project}", parentSubpath: "01_Shoots",
  folders: ["01_Media/Camera", "01_Media/Audio", "02_Edit/Premiere", "03_Exports"],
  mediaFolder: "01_Media/Camera", fileNameTemplate: "{date:yyMMdd}_{code}_{reel}_{seq:0000}",
  folderNameTemplate: "{date:yyMMdd}_{code}", separator: "_", renameOnIngest: false,
  copyLocations: 2, premiereProject: true,
};
const profile = buildConfiguredDelivery(request).profile;
fs.writeFileSync(validPath, JSON.stringify(profile));
const invalid = structuredClone(profile);
invalid.team.workflows[0].mediaFolder = "99_Missing";
fs.writeFileSync(invalidPath, JSON.stringify(invalid));
NODE

log_path="$fixture_dir/xcodebuild.log"
xcodebuild -project app/VaultlineIngest.xcodeproj \
  -scheme VaultlineIngest -configuration Debug -destination 'platform=macOS' test \
  -only-testing:VaultlineIngestTests/TeamWorkflowTests/testWebsiteGeneratedProfileDecodesAndRejectsInvalidProfile \
  2>&1 | tee "$log_path"
if ! rg -F "Test Case '-[VaultlineIngestTests.TeamWorkflowTests testWebsiteGeneratedProfileDecodesAndRejectsInvalidProfile]' passed" "$log_path" >/dev/null; then
  echo "targeted parity test did not execute and pass" >&2
  exit 1
fi
