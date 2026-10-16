"""Run pure guide decisions/replays on macOS without building or installing the iOS app.

The API endpoint test stays in the iOS test target; it needs the app networking stack.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="pippipgo-guide-") as directory:
    package = Path(directory)
    source = package / "Sources/pippipgo"
    tests = package / "Tests/pippipgoTests"
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    shutil.copy(ROOT / "pippipgo/Intelligence/LiveGuideEngine.swift", source)
    shutil.copy(ROOT / "pippipgoTests/LiveGuideEngineTests.swift", tests)
    # The engine localizes its default tour name through the real app language
    # preference. Include that definition without the @main app and its stores.
    app_source = (ROOT / "pippipgo/App/pippipgoApp.swift").read_text()
    language_start = app_source.index("enum AppLanguage:")
    language_end = app_source.index("\nstruct AppLanguageMenu:", language_start)
    (source / "AppLanguage.swift").write_text(
        "import SwiftUI\n\n" + app_source[language_start:language_end] + "\n"
    )
    (package / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "GuideLogic", platforms: [.macOS(.v14)], targets: [
    .target(name: "pippipgo"),
    .testTarget(name: "pippipgoTests", dependencies: ["pippipgo"])
])
''')
    environment = dict(os.environ)
    xcode = Path("/Applications/Xcode.app/Contents/Developer")
    if xcode.exists():
        environment.setdefault("DEVELOPER_DIR", str(xcode))
    result = subprocess.run(["swift", "test", "--package-path", str(package)], env=environment)
    raise SystemExit(result.returncode)
