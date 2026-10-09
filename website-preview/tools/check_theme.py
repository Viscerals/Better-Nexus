"""Browser checks against an isolated, locally served MkDocs build."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread
import json
import re

from playwright.sync_api import sync_playwright, expect

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / "qa"
QA.mkdir(exist_ok=True)
ROUTES = ["", "guide/", "guide/install/", "guide/first-wishlist/",
          "guide/features/", "guide/troubleshooting/", "releases/",
          "releases/changelog/", "support/"]
PREFIX = "/Better-Nexus/"
release = json.loads((ROOT / "release-source.json").read_text(encoding="utf-8"))

class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith(PREFIX):
            self.path = self.path.removeprefix("/Better-Nexus")
        super().do_GET()

    def log_message(self, *_):
        pass

server = ThreadingHTTPServer(("127.0.0.1", 0), partial(Handler, directory=str(ROOT / "site")))
Thread(target=server.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{server.server_port}{PREFIX}"
results = []

# Measure normal text against the actual composited ancestor background.
CONTRAST = r"""() => {
  const rgb = value => (value.match(/[\d.]+/g) || []).map(Number);
  const over = (front, back) => {
    const alpha = front.length < 4 ? 1 : front[3];
    return front.slice(0, 3).map((v, i) => v * alpha + back[i] * (1 - alpha));
  };
  const background = el => {
    const chain = [];
    for (let node = el; node; node = node.parentElement) chain.unshift(node);
    return chain.reduce((back, node) => over(rgb(getComputedStyle(node).backgroundColor), back), [255, 255, 255]);
  };
  const luminance = color => color.map(v => {
    v /= 255;
    return v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4;
  }).reduce((sum, v, i) => sum + v * [.2126, .7152, .0722][i], 0);
  return [...document.querySelectorAll('.md-content p, .md-content h1, .md-content h2, .md-content h3, .md-content li, .md-content a, .md-content th, .md-content td, .nx-eyebrow, .nx-route-number, .nx-route-link, .nx-facts span, .nx-release-label, .nx-pill')].filter(el => {
    const style = getComputedStyle(el);
    return el.textContent.trim() && el.getClientRects().length && style.visibility !== 'hidden';
  }).map(el => {
    const style = getComputedStyle(el);
    const back = background(el), front = over(rgb(style.color), back);
    const a = luminance(front), b = luminance(back);
    const ratio = (Math.max(a, b) + .05) / (Math.min(a, b) + .05);
    const size = parseFloat(style.fontSize);
    const large = size >= 24 || (size >= 18.66 && parseFloat(style.fontWeight) >= 700);
    return {text: el.textContent.trim().slice(0, 70), ratio, minimum: large ? 3 : 4.5};
  });
}"""

def scheme(page, expected):
    expect(page.locator("body")).to_have_attribute("data-md-color-scheme", expected)

def inspect(page, route, mode, width):
    assert page.evaluate("document.documentElement.scrollWidth <= innerWidth"), (route, mode, width, "overflow")
    measured = page.evaluate(CONTRAST)
    failed = [item for item in measured if item["ratio"] + .01 < item["minimum"]]
    assert not failed, (route, mode, width, "contrast", failed)
    results.append({"route": route, "mode": mode, "width": width,
                    "text_samples": len(measured),
                    "minimum_contrast": round(min(item["ratio"] for item in measured), 2)})
    if route in ("", "guide/install/", "releases/", "support/"):
        name = route.strip("/").replace("/", "-") or "home"
        page.screenshot(path=str(QA / f"{name}-{mode}-{width}.png"), full_page=True)

try:
    with sync_playwright() as p:
        # Use the runner's existing Chrome; do not install a native browser.
        browser = p.chromium.launch(channel="chrome", headless=True)
        for width, height in ((1440, 1000), (390, 844), (320, 740)):
            context = browser.new_context(viewport={"width": width, "height": height}, color_scheme="light")
            page = context.new_page()
            errors = []
            page.on("pageerror", lambda error: errors.append(str(error)))
            for route in ROUTES:
                page.goto(BASE + route)
                scheme(page, "slate")
                inspect(page, route, "dark", width)
            page.goto(BASE)
            light = page.get_by_role("button", name="Switch to light mode", exact=True)
            expect(light).to_be_visible()
            light.press("Enter")
            scheme(page, "default")
            expect(page.get_by_role("button", name="Switch to dark mode", exact=True)).to_be_focused()
            for route in ROUTES:
                page.goto(BASE + route)
                scheme(page, "default")
                page.reload()
                scheme(page, "default")
                inspect(page, route, "light", width)
            page.get_by_role("button", name="Switch to dark mode", exact=True).press("Space")
            scheme(page, "slate")
            expect(page.get_by_role("button", name="Switch to light mode", exact=True)).to_be_focused()
            page.reload()
            scheme(page, "slate")
            page.goto(BASE + "guide/install/")
            if width < 1150:
                page.get_by_role("button", name="Open navigation", exact=True).press("Enter")
                expect(page.locator("#__drawer")).to_be_checked()
                page.get_by_role("link", name="Troubleshooting", exact=True).click()
                expect(page).to_have_url(BASE + "guide/troubleshooting/")
                page.get_by_role("button", name="Open search", exact=True).press("Space")
                expect(page.locator("#__search")).to_be_checked()
            else:
                page.get_by_role("textbox", name="Search", exact=True).fill("Wishlist")
                expect(page.locator(".md-search-result__list")).to_contain_text("Wishlist")
            assert not errors, errors
            context.close()

        # Default HTML and CSS must stay dark even without executable scripts.
        context = browser.new_context(java_script_enabled=False, color_scheme="light")
        page = context.new_page()
        page.goto(BASE)
        scheme(page, "slate")
        assert page.locator("body").evaluate("el => getComputedStyle(el).backgroundColor") == "rgb(29, 30, 34)"
        page.screenshot(path=str(QA / "first-paint-no-js.png"), full_page=True)
        context.close()

        # Saved light is applied before asynchronous scripts can load.
        context = browser.new_context()
        page = context.new_page()
        page.goto(BASE)
        page.get_by_role("button", name="Switch to light mode", exact=True).click()
        scheme(page, "default")
        page.route("**/assets/javascripts/bundle.*.js", lambda route: route.abort())
        page.route("**/javascripts/accessibility.js*", lambda route: route.abort())
        page.reload()
        scheme(page, "default")
        assert page.locator("body").evaluate("el => getComputedStyle(el).backgroundColor") == "rgb(249, 248, 252)"
        context.close()

        # Recorded release URLs and current labels survive the theme change.
        context = browser.new_context()
        page = context.new_page()
        page.goto(BASE)
        expect(page.locator(".nx-release-label")).to_contain_text(release["tag_name"].split("-")[-1])
        expect(page.get_by_role("link", name="Get Better Nexus")).to_have_attribute("href", "releases/")
        page.goto(BASE + "releases/")
        for asset in release["assets"]:
            assert page.locator(f'a[href="{asset["browser_download_url"]}"]').count()
        assert not page.get_by_role("link", name=re.compile("roadmap", re.I)).count()
        context.close()
        browser.close()
finally:
    server.shutdown()

(QA / "theme-check.json").write_text(json.dumps({"cases": results, "errors": []}, indent=2), encoding="utf-8")
print(json.dumps({"theme_page_cases": len(results), "viewports": [1440, 390, 320],
                  "keyboard_toggle_persistence_mobile_first_paint": "passed",
                  "errors": []}, indent=2))
