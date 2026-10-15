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
