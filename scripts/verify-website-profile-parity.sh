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

temp_root="/tmp/vlp-657-profile-parity"
rm -rf "$temp_root"
mkdir -p "$temp_root"
trap 'rm -rf "$temp_root"' EXIT
valid_profile="$temp_root/website-profile.json"
invalid_profile="$temp_root/website-invalid-profile.json"

node - "$website_root" "$valid_profile" "$invalid_profile" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const [websiteRoot, validPath, invalidPath] = process.argv.slice(2);
const { buildConfiguredDelivery } = require(path.join(websiteRoot, "api", "_ingest-config.js"));
const request = {
  email: "jordan@example.test",
  teamName: "Northstar",
  confirmed: true,
  permission_to_follow_up: "yes",
  website: "",
  scan: { sampleSize: 120, consistency: 0.84 },
  fields: ["shootDate", "project", "jobNumber", "camera", "reel", "notes"],
  jobNameTemplate: "{date:yyMMdd}_{jobNumber}_{project}",
  parentSubpath: "01_Shoots",
  folders: ["01_Media/Camera", "01_Media/Audio", "02_Edit/Premiere", "03_Exports"],
  mediaFolder: "01_Media/Camera",
  fileNameTemplate: "{date:yyMMdd}_{code}_{reel}_{seq:0000}",
  folderNameTemplate: "{date:yyMMdd}_{code}",
  separator: "_",
  renameOnIngest: false,
  copyLocations: 2,
  premiereProject: true,
};
const profile = buildConfiguredDelivery(request).profile;
fs.writeFileSync(validPath, JSON.stringify(profile));
const invalid = structuredClone(profile);
invalid.team.workflows[0].mediaFolder = "99_Missing";
fs.writeFileSync(invalidPath, JSON.stringify(invalid));
NODE

WEBSITE_PROFILE_PATH="$valid_profile" \
WEBSITE_INVALID_PROFILE_PATH="$invalid_profile" \
xcodebuild -project app/VaultlineIngest.xcodeproj \
  -scheme VaultlineIngest -configuration Debug -destination 'platform=macOS' test \
  -only-testing:VaultlineIngestTests/TeamWorkflowTests/testWebsiteGeneratedProfileDecodesAndRejectsInvalidProfile
