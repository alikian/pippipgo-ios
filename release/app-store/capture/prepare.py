from pathlib import Path
import shutil
import tempfile

repo = Path(__file__).resolve().parents[3]
checkout = Path(tempfile.mkdtemp(prefix='pippipgo-screenshots-', dir='/private/tmp'))
for name in ['pippipgo', 'pippipgo.xcodeproj', 'Configurations', 'Resources']:
    shutil.copytree(repo / name, checkout / name)
entry = checkout / 'pippipgo/App/pippipgoApp.swift'
text = entry.read_text()
start = text.index('            RootView(store: authenticationStore)')
end = text.index('\n        }', start)
text = text[:start] + '            ScreenshotGallery()' + text[end:]
entry.write_text(text + '\n' + Path(__file__).with_name('ScreenshotFixture.swift').read_text())
print(checkout)

# Allow fictional transcript injection only in this disposable capture checkout.
voice = checkout / 'pippipgo/Intelligence/LiveVoice.swift'
voice.write_text(voice.read_text().replace('private(set) var transcript', 'var transcript'))

# Capture-only visibility and deterministic public location; no shipping behavior changes.
guide = checkout / 'pippipgo/Intelligence/LiveGuide.swift'
text = guide.read_text().replace('private struct TourBuilderView:', 'struct TourBuilderView:')
text = text.replace('private(set) var suggestedTour', 'var suggestedTour').replace('private(set) var tourDraft', 'var tourDraft')
start = text.index('    func start(background: Bool = false) {')
end = text.index('\n    private func begin()', start)
text = text[:start] + '''    func start(background: Bool = false) {
        onLocation(CLLocation(coordinate: CLLocationCoordinate2D(latitude: 34.0159, longitude: -118.5025), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date()))
    }
''' + text[end:]
guide.write_text(text)
# Hide only the diagnostic environment badge in the disposable capture copy.
guide.write_text(guide.read_text().replace('if AppConfiguration.live.environment != .prod {', 'if false {'))
