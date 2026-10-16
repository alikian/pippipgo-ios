"""Validate and package native App Store images; no screenshots are resized."""
from pathlib import Path
from PIL import Image, ImageDraw
import hashlib
import html
import json
import shutil
import zipfile

root = Path(__file__).resolve().parent.parent / 'submission-2026-10-15'
groups = {'iphone-medium': (1206, 2622), 'iphone-large': (1320, 2868), 'ipad-13': (2064, 2752)}
titles = ['Explore at your pace', 'Create a tour around your interests', 'Preview your tour', 'Ask Pip for travel ideas', 'Translate a conversation', 'Keep your trips together']
manifest = []
for group, size in groups.items():
    files = sorted((root / group).glob('*.png'))
    assert len(files) == 6, (group, len(files))
    for path in files:
        with Image.open(path) as image:
            assert image.size == size, (path, image.size)
            if 'A' in image.getbands():
                assert image.getchannel('A').getextrema() == (255, 255), path
            image.convert('RGB').save(path, optimize=True)
        manifest.append({'file': str(path.relative_to(root)), 'width': size[0], 'height': size[1], 'mode': 'RGB', 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
assets = root / 'app-icon'
assets.mkdir(exist_ok=True)
shutil.copyfile(root.parents[2] / 'Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png', assets / 'AppIcon-1024.png')
with Image.open(assets / 'AppIcon-1024.png') as image:
    assert image.size == (1024, 1024) and image.mode == 'RGB'
(root / 'assets.json').write_text(json.dumps(manifest, indent=2) + '\n')
(root / 'captions.txt').write_text('\n'.join(f'{i:02d}. {title}' for i, title in enumerate(titles, 1)) + '\n')
(root / 'README.txt').write_text('''PipPipGo — App Store submission images
Prepared October 15, 2026. English (en-US).

UPLOAD THESE PNGS
iphone-medium: 6 native iPhone 16 Pro screenshots, 1206 x 2622.
iphone-large: 6 additional native iPhone 16 Pro Max screenshots, 1320 x 2868.
ipad-13: 6 native iPad Pro 13-inch screenshots, 2064 x 2752.
Use the numbered order within each group. Do not upload this gallery or contact sheets.

APP ICON
app-icon/AppIcon-1024.png is the existing production 1024 x 1024 RGB icon.
The app icon is normally delivered through the app build's asset catalog.
App-preview videos and promotional artwork are optional and are not included.
This package targets the iOS/iPadOS app, not separate Mac, Watch, TV or Vision apps.

CAPTURE AND VALIDATION
Native portrait simulator captures from the current source views. No image was
resized, stretched, retouched or composited for upload. Fully opaque alpha
channels were removed losslessly; all upload PNGs are RGB. Dimensions and hashes
are listed in assets.json. Apple Maps attribution remains visible.

An isolated screenshot-only build uses com.pippipgo.screenshots. Fictional
profiles, trips, conversations, translations and a sample Santa Monica tour are
injected into actual app views. Native modal presentation is retained for tour
screens. Public Santa Monica map tiles and Apple route previews may load from
Apple; no real traveler data or live backend/OpenAI requests were used. The
capture shell opens existing screens directly and suppresses Dev badges. It is
not shipped and does not prove provider/device acceptance or release readiness.
No release build number was assigned and no App Store upload was performed.

Before submission, pair these images with a build containing the depicted UI.
Dev/Prod backend rollout for area/activity tour support remains separate.

REQUIREMENTS CHECKED
https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
https://developer.apple.com/help/app-store-connect/manage-app-information/add-an-app-icon

REPRODUCE
Run capture/prepare.py, build the returned isolated project with Dev for arm64
simulator and PRODUCT_BUNDLE_IDENTIFIER=com.pippipgo.screenshots, then run
capture/capture.py BUILD_DIRECTORY SIMULATOR_UUID SIZE_GROUP for each device.
Run capture/package.py after captures finish (requires Pillow).
''')
sections=[]
for group in groups:
    figures=''.join(f'<figure><a href="{group}/{p.name}"><img loading="lazy" src="{group}/{p.name}" alt="{html.escape(titles[i])}"></a><figcaption>{i+1}. {html.escape(titles[i])}</figcaption></figure>' for i,p in enumerate(sorted((root/group).glob('*.png'))))
    sections.append(f'<section><h2>{group}</h2><div class="grid">{figures}</div></section>')
(root/'index.html').write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>PipPipGo — App Store images</title><style>body{font:16px system-ui;margin:32px auto;max-width:1400px;padding:0 20px;background:#f3f5f8;color:#172035}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:20px}figure{margin:0;background:white;padding:12px;border-radius:16px}img{width:100%;height:auto;display:block}figcaption{padding-top:12px}h2{margin-top:40px}a{color:#075bd7}</style><h1>PipPipGo — App Store images</h1><p>18 native screenshots and the production app icon. Click a screenshot to open its original PNG.</p><p>Fictional sample data · English · October 15, 2026</p>'''+''.join(sections)+'</html>')
# Review-only contact sheets are kept outside the upload package.
for group in groups:
    sheet=Image.new('RGB',(1200,900),'#e5e7eb');draw=ImageDraw.Draw(sheet)
    for i,p in enumerate(sorted((root/group).glob('*.png'))):
        with Image.open(p) as image:
            image.thumbnail((370,400));x=i%3*400+(400-image.width)//2;y=i//3*450+28
            sheet.paste(image,(x,y));draw.text((i%3*400+12,i//3*450+8),p.stem,fill='black')
    sheet.save(root.parent / f'submission-2026-10-15-{group}-contact-sheet.jpg')
for group in groups:
    with zipfile.ZipFile(root.parent / f'pippipgo-submission-2026-10-15-{group}.zip','w',zipfile.ZIP_DEFLATED) as z:
        for p in sorted((root/group).glob('*.png')):z.write(p,p.name)
archive=root.parent/'pippipgo-app-store-submission-2026-10-15.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(root.rglob('*')):
        if p.is_file():z.write(p,p.relative_to(root))
print(f'Validated {len(manifest)} screenshots; packaged {archive}')
