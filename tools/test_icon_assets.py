import hashlib
import json
import unittest
import generate_icon_atlas as icons


class IconAssets(unittest.TestCase):
    def test_shader_sources_and_artifacts_match_recorded_hashes(self):
        root = icons.ROOT / 'native/sdl_gpu/icon_shaders'
        manifest = json.loads((root / 'manifest.json').read_text())
        for name, expected in manifest['sha256'].items():
            self.assertEqual(hashlib.sha256((root / name).read_bytes()).hexdigest(), expected, name)

    def test_rejects_external_resources_and_non_monochrome_art(self):
        for content in [b'<image href="https://example.com/a.png"/>', b'<script/>',
                        b'<path d="M0 0" fill="url(#paint)"/>', b'<path d="M0 0" fill="red"/>',
                        b'<text>Glyph</text>', b'<path d="M0 0" opacity="0.5"/>']:
            with self.subTest(content=content), self.assertRaises(ValueError):
                icons.validate_svg(b'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">' + content + b'</svg>')

    def test_rejects_entity_declarations(self):
        with self.assertRaises(ValueError):
            icons.validate_svg(b'<!DOCTYPE svg><svg/>')

    def test_extracts_alpha_not_rgb_luminance(self):
        path = icons.ROOT / 'out/icon-generation/alpha-test.png'
        path.parent.mkdir(parents=True, exist_ok=True)
        pixels = bytes([0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 128, 0, 0, 0, 255])
        path.write_bytes(icons.png_rgba(2, 2, pixels))
        self.assertEqual(icons.read_alpha(path, 2), bytes([0, 64, 128, 255]))


if __name__ == '__main__':
    unittest.main()
