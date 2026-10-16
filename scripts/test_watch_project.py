"""Validate watch target wiring and resources without Xcode or a device.

This does not compile Swift or prove paired-device behavior.
"""
from pathlib import Path
import json
import re
import struct
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def read_project():
    source = (ROOT / "pippipgo.xcodeproj/project.pbxproj").read_text()
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|/\*[\s\S]*?\*/|//[^\n]*|[{}()=;,]|[^\s{}()=;,]+', source)
    tokens = [token for token in tokens if not token.startswith(("//", "/*"))]
    index = 0

    def take(expected=None):
        nonlocal index
        token = tokens[index]
        index += 1
        if expected is not None and token != expected:
            raise ValueError(f"Expected {expected!r}, got {token!r}")
        return token

    def value():
        token = take()
        if token == "{":
            result = {}
            while tokens[index] != "}":
                key = take()
                key = json.loads(key) if key.startswith('"') else key
                take("=")
                if key in result:
                    raise ValueError(f"Duplicate key: {key}")
                result[key] = value()
                take(";")
            take("}")
            return result
        if token == "(":
            result = []
            while tokens[index] != ")":
                result.append(value())
                if tokens[index] == ",":
                    take(",")
                elif tokens[index] != ")":
                    raise ValueError("Missing array delimiter")
            take(")")
            return result
        return json.loads(token) if token.startswith('"') else token

    result = value()
    if index != len(tokens):
        raise ValueError("Unparsed project content")
    return result


class WatchProjectTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.project = read_project()
        cls.objects = cls.project["objects"]
        cls.watch_id, cls.watch = next((key, value) for key, value in cls.objects.items()
                                      if value.get("isa") == "PBXNativeTarget" and value.get("name") == "pippipgoWatch")
        cls.phone = next(value for value in cls.objects.values()
                         if value.get("isa") == "PBXNativeTarget" and value.get("name") == "pippipgo")

    def test_all_object_references_resolve(self):
        def visit(value):
            if isinstance(value, dict):
                for child in value.values():
                    visit(child)
            elif isinstance(value, list):
                for child in value:
                    visit(child)
            elif re.fullmatch(r"[A-F0-9]{24}", value):
                self.assertIn(value, self.objects)
        visit(self.project)

    def test_iphone_embeds_and_builds_watch(self):
        dependencies = [self.objects[key]["target"] for key in self.phone["dependencies"]]
        self.assertIn(self.watch_id, dependencies)
        copies = [self.objects[key] for key in self.phone["buildPhases"]
                  if self.objects[key]["isa"] == "PBXCopyFilesBuildPhase"]
        embed = next(phase for phase in copies if phase["name"] == "Embed Watch Content")
        self.assertEqual(embed["dstPath"], "$(CONTENTS_FOLDER_PATH)/Watch")
        build = self.objects[embed["files"][0]]
        self.assertEqual(build["fileRef"], self.watch["productReference"])

    def test_all_configurations_pair_with_existing_app_and_share_version(self):
        configs = self.objects[self.watch["buildConfigurationList"]]["buildConfigurations"]
        self.assertEqual({self.objects[key]["name"] for key in configs}, {"Local", "Dev", "Prod"})
        for key in configs:
            config = self.objects[key]
            base = self.objects[config["baseConfigurationReference"]]
            self.assertEqual(base["path"], "Configurations/Common.xcconfig")
            settings = config["buildSettings"]
            self.assertEqual(settings["PRODUCT_BUNDLE_IDENTIFIER"], "com.pippipgo.ios.watchkitapp")
            self.assertEqual(settings["INFOPLIST_KEY_WKCompanionAppBundleIdentifier"], "com.pippipgo.ios")
            self.assertEqual(settings["INFOPLIST_KEY_WKApplication"], "YES")
            self.assertEqual(settings["INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp"], "NO")
            self.assertEqual(settings["WATCHOS_DEPLOYMENT_TARGET"], "10.0")
            self.assertEqual(settings["SDKROOT"], "watchos")
            self.assertNotIn("CURRENT_PROJECT_VERSION", settings)

    def test_shared_protocol_is_compiled_for_phone_and_watch(self):
        for target in [self.phone, self.watch]:
            paths = []
            for key in target["buildPhases"]:
                phase = self.objects[key]
                if phase["isa"] == "PBXSourcesBuildPhase":
                    for item in phase["files"]:
                        paths.append(self.objects[self.objects[item]["fileRef"]]["path"])
            self.assertIn("Shared/WatchControlProtocol.swift", paths)
            self.assertEqual(len(paths), len(set(paths)))
            for path in paths:
                self.assertTrue((ROOT / path).is_file(), path)

    def test_watch_resources_and_localizations_exist(self):
        catalog = json.loads((ROOT / "pippipgoWatch/Localizable.xcstrings").read_text())
        languages = {"en", "fa", "ja", "es", "fr", "it", "zh-Hans", "ko", "vi", "fil", "fil-PH", "tr", "ar", "ru"}
        for key, entry in catalog["strings"].items():
            self.assertTrue(languages.issubset(entry["localizations"]), key)
            for language in languages:
                self.assertTrue(entry["localizations"][language]["stringUnit"]["value"])
        icon = ROOT / "pippipgoWatch/Assets.xcassets/AppIcon.appiconset"
        spec = json.loads((icon / "Contents.json").read_text())
        data = (icon / spec["images"][0]["filename"]).read_bytes()
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(struct.unpack(">II", data[16:24]), (1024, 1024))

    def test_watch_scheme_references_watch_target(self):
        scheme = ET.parse(ROOT / "pippipgo.xcodeproj/xcshareddata/xcschemes/Watch.xcscheme")
        for reference in scheme.findall(".//BuildableReference"):
            self.assertEqual(reference.attrib["BlueprintIdentifier"], self.watch_id)
        self.assertEqual(scheme.find(".//ArchiveAction").attrib["buildConfiguration"], "Prod")


if __name__ == "__main__":
    unittest.main()
