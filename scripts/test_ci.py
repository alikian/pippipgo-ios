"""Exercise cloud hooks in throwaway checkouts; no Apple/AWS access or uploads."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROD_CLIENT = "23sk8qfmpotjj40jbnl9tn33em"
VERSION = next(line.split(" = ", 1)[1] for line in
               (ROOT / "Configurations/Version.xcconfig").read_text().splitlines()
               if line.startswith("MARKETING_VERSION = "))


class CloudHookTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pippipgo-ci-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for directory in ("ci_scripts", "Configurations", "scripts"):
            shutil.copytree(ROOT / directory, self.root / directory)
        for name in ("ProdIdentity.xcconfig", "CIOverrides.xcconfig"):
            (self.root / "Configurations" / name).unlink(missing_ok=True)
        self.env = dict(os.environ, CI_PRIMARY_REPOSITORY_PATH=str(self.root),
                        CI_BUILD_NUMBER="42", CI_XCODE_SCHEME="Prod",
                        PIPPIPGO_PROD_COGNITO_CLIENT_ID=PROD_CLIENT,
                        CI_XCODEBUILD_ACTION="archive", CI_XCODEBUILD_EXIT_CODE="0")

    def run_hook(self, name, success=True):
        result = subprocess.run([str(self.root / "ci_scripts" / name)],
                                env=self.env, capture_output=True, text=True,
                                cwd=self.root / "ci_scripts")
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)

    def test_fresh_checkout_gets_cloud_number_and_prod_identity(self):
        self.run_hook("ci_post_clone.sh")
        self.assertIn("CURRENT_PROJECT_VERSION = 42", self.overrides())
        self.assertIn(PROD_CLIENT, (self.root / "Configurations/Prod.xcconfig").read_text())
        self.assertFalse((self.root / "Configurations/ProdIdentity.xcconfig").exists())
        self.env["CI_BUILD_NUMBER"] = "43"
        self.run_hook("ci_post_clone.sh")
        self.assertIn("CURRENT_PROJECT_VERSION = 43", self.overrides())
        self.assertNotIn("42", self.overrides())

    def overrides(self):
        return (self.root / "Configurations/CIOverrides.xcconfig").read_text()

    def test_dev_or_invalid_workflow_identity_cannot_build_prod(self):
        for value in ("5ungc4grbiid7de7rjbh0jn2ff", "invalid\nSETTING = value"):
            with self.subTest(value=value):
                self.env["PIPPIPGO_PROD_COGNITO_CLIENT_ID"] = value
                self.run_hook("ci_post_clone.sh", success=False)

    def test_prod_builds_without_workflow_identity(self):
        self.env.pop("PIPPIPGO_PROD_COGNITO_CLIENT_ID")
        self.run_hook("ci_post_clone.sh")
        self.assertIn("CURRENT_PROJECT_VERSION = 42", self.overrides())

    def test_wrong_checked_in_prod_identity_is_rejected(self):
        path = self.root / "Configurations/Prod.xcconfig"
        path.write_text(path.read_text().replace(PROD_CLIENT, "5ungc4grbiid7de7rjbh0jn2ff"))
        self.run_hook("ci_post_clone.sh", success=False)

    def test_invalid_build_numbers_are_rejected(self):
        for number in ("", "0", "01", "-1", "1.2", "42\nSETTING = value"):
            with self.subTest(number=number):
                self.env["CI_BUILD_NUMBER"] = number
                self.run_hook("ci_post_clone.sh", success=False)

    def test_dev_tests_need_no_prod_identity(self):
        self.env.update(CI_XCODE_SCHEME="Dev", CI_XCODEBUILD_ACTION="build-for-testing")
        self.env.pop("PIPPIPGO_PROD_COGNITO_CLIENT_ID")
        self.run_hook("ci_pre_xcodebuild.sh")
        self.assertFalse((self.root / "Configurations/ProdIdentity.xcconfig").exists())

    def test_dev_can_archive_without_prod_identity(self):
        self.env["CI_XCODE_SCHEME"] = "Dev"
        self.env.pop("PIPPIPGO_PROD_COGNITO_CLIENT_ID")
        self.run_hook("ci_pre_xcodebuild.sh")

    def test_local_and_unknown_cannot_archive(self):
        for scheme in ("Local", "Unknown"):
            self.env["CI_XCODE_SCHEME"] = scheme
            self.run_hook("ci_pre_xcodebuild.sh", success=False)

    def test_testability_does_not_leak_into_archive(self):
        for action in ("build-for-testing", "test-without-building"):
            self.env["CI_XCODEBUILD_ACTION"] = action
            self.run_hook("ci_pre_xcodebuild.sh")
            self.assertIn("ENABLE_TESTABILITY = YES", self.overrides())
        self.env["CI_XCODEBUILD_ACTION"] = "archive"
        self.run_hook("ci_pre_xcodebuild.sh")
        self.assertIn("ENABLE_TESTABILITY = NO", self.overrides())
        self.assertNotIn("ENABLE_TESTABILITY = YES", self.overrides())

    def archive(self):
        archive = self.root / "PipPipGo.xcarchive"
        app = archive / "Products/Applications/pippipgo.app"
        app.mkdir(parents=True)
        self.env["CI_ARCHIVE_PATH"] = str(archive)
        return app / "Info.plist"

    def test_archive_checks_actual_built_identity_and_version(self):
        plist = self.archive()
        expected = dict(CFBundleIdentifier="com.pippipgo.ios", CFBundleDisplayName="PipPipGo",
                        AppEnvironment="prod", BackendBaseURL="https://api.pippipgo.com",
                        CognitoDomain="https://auth.pippipgo.com", CognitoClientID=PROD_CLIENT,
                        CFBundleVersion="42", CFBundleShortVersionString=VERSION,
                        UISupportedInterfaceOrientations=[
                            "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
                            "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
                        CFBundleURLTypes=[{"CFBundleURLSchemes": ["pippipgo"]}])
        plist.write_bytes(plistlib.dumps(expected))
        self.run_hook("ci_post_xcodebuild.sh")
        self.env["CI_XCODE_SCHEME"] = "Dev"
        dev = dict(expected, CFBundleDisplayName="PipPipGo Dev", AppEnvironment="dev",
                   BackendBaseURL="https://api-dev.pippipgo.com",
                   CognitoDomain="https://auth-dev.pippipgo.com",
                   CognitoClientID="5ungc4grbiid7de7rjbh0jn2ff")
        plist.write_bytes(plistlib.dumps(dev))
        self.run_hook("ci_post_xcodebuild.sh")
        plist.write_bytes(plistlib.dumps(expected))
        self.run_hook("ci_post_xcodebuild.sh", success=False)
        self.env["CI_XCODE_SCHEME"] = "Prod"
        plist.write_bytes(plistlib.dumps(dev))
        self.run_hook("ci_post_xcodebuild.sh", success=False)
        for field, value in dict(CFBundleURLTypes=[{"CFBundleURLSchemes": ["pipgogo"]}],
                                 UISupportedInterfaceOrientations=[],
                                 **{"UISupportedInterfaceOrientations~ipad": ["UIInterfaceOrientationPortrait"]},
                                 BackendBaseURL="https://api-dev.pippipgo.com",
                                 CognitoClientID="5ungc4grbiid7de7rjbh0jn2ff",
                                 CFBundleVersion="1", CFBundleShortVersionString=VERSION + ".99",
                                 NSAppTransportSecurity={"NSAllowsArbitraryLoads": True}).items():
            with self.subTest(field=field):
                plist.write_bytes(plistlib.dumps(dict(expected, **{field: value})))
                self.run_hook("ci_post_xcodebuild.sh", success=False)

    def test_failed_build_remains_failed(self):
        self.env["CI_XCODEBUILD_EXIT_CODE"] = "65"
        self.run_hook("ci_post_xcodebuild.sh", success=False)

    def test_missing_archive_fails(self):
        self.env.pop("CI_ARCHIVE_PATH", None)
        self.run_hook("ci_post_xcodebuild.sh", success=False)

    def test_successful_test_action_does_not_require_archive(self):
        self.env["CI_XCODEBUILD_ACTION"] = "test-without-building"
        self.run_hook("ci_post_xcodebuild.sh")


if __name__ == "__main__":
    unittest.main()
