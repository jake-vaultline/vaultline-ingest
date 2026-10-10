import json, re, tempfile, unittest, uuid
from pathlib import Path
from ingest_fulfillment import fulfill, verify, FulfillmentError, RELEASE

HERE=Path(__file__).parent
class FulfillmentTests(unittest.TestCase):
  def test_package_and_tamper_detection(self):
    with tempfile.TemporaryDirectory() as td:
      result=fulfill(HERE/"example-request.json",td)
      self.assertEqual(result["state"],"release-bound"); self.assertEqual(verify(td)["state"],"verified")
      profile=json.loads((Path(td)/"Vaultline-Ingest-Team-Profile.json").read_text())
      self.assertEqual(profile["naming"]["fileTemplate"],"{date:yyMMdd}_{code}_{reel}_{seq:0000}")
      for field in profile["form"]["fields"]: uuid.UUID(field["id"])
      self.assertIn("expects 2 destination location(s)",(Path(td)/"GETTING-STARTED.md").read_text())
      (Path(td)/"GETTING-STARTED.md").write_text("changed")
      with self.assertRaises(FulfillmentError): verify(td)
  def test_ambiguity_stops_before_configuration(self):
    with tempfile.TemporaryDirectory() as td:
      request=json.loads((HERE/"example-request.json").read_text()); request["openQuestions"]=["Confirm media landing"]
      p=Path(td)/"request.json"; p.write_text(json.dumps(request))
      self.assertEqual(fulfill(p,Path(td)/"out")["state"],"clarification")
  def test_invalid_path_and_token_fail_closed(self):
    for mutation in ("path","token"):
      with tempfile.TemporaryDirectory() as td:
        r=json.loads((HERE/"example-request.json").read_text())
        if mutation=="path": r["resolved"]["workflows"][0]["folders"][0]="../escape"
        else: r["resolved"]["workflows"][0]["jobNameTemplate"]="{invented}"
        p=Path(td)/"r.json"; p.write_text(json.dumps(r))
        with self.assertRaises(FulfillmentError): fulfill(p,Path(td)/"out")
  def test_unsupported_naming_token_fails_closed(self):
    with tempfile.TemporaryDirectory() as td:
      r=json.loads((HERE/"example-request.json").read_text())
      r["resolved"]["naming"]["fileTemplate"]="{clientSecret}_{seq:0000}"
      p=Path(td)/"r.json"; p.write_text(json.dumps(r))
      with self.assertRaises(FulfillmentError): fulfill(p,Path(td)/"out")
  def test_install_script_pin_matches_release(self):
    install_sh=(HERE.parent/"download/install.sh").read_text()
    version_match=re.search(r'VERSION="([^"]+)"',install_sh)
    sha256_match=re.search(r'SHA256="([^"]+)"',install_sh)
    self.assertIsNotNone(version_match,"VERSION not found in install.sh")
    self.assertIsNotNone(sha256_match,"SHA256 not found in install.sh")
    version=version_match.group(1)
    sha256=sha256_match.group(1)
    self.assertEqual(version,RELEASE["version"],f"VERSION in install.sh ({version}) does not match RELEASE version ({RELEASE['version']})")
    self.assertEqual(sha256,RELEASE["sha256"],f"SHA256 in install.sh ({sha256}) does not match RELEASE sha256 ({RELEASE['sha256']})")
    base_match=re.search(r'BASE="([^"]+)"',install_sh)
    dmg_match=re.search(r'DMG="([^"]+)"',install_sh)
    self.assertIsNotNone(base_match,"BASE not found in install.sh")
    self.assertIsNotNone(dmg_match,"DMG not found in install.sh")
    base_raw=base_match.group(1)
    dmg=dmg_match.group(1)
    base_expanded=base_raw.replace("${VERSION}",version)
    dmg_expanded=dmg.replace("${VERSION}",version)
    resolved_url=f"{base_expanded}/{dmg_expanded}"
    self.assertEqual(resolved_url,RELEASE["dmgURL"],f"Resolved URL ({resolved_url}) does not match RELEASE dmgURL ({RELEASE['dmgURL']})")
if __name__=="__main__": unittest.main()
