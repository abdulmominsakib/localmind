from pathlib import Path
import tempfile
import unittest

from check_docs import anchors, check_links, check_pub_links, destinations, documents


class DocumentationTest(unittest.TestCase):
    def test_pub_links_reject_relative_paths_even_when_targets_exist(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            readme = root / "README.md"
            (root / "guide.md").write_text("# Guide\n")
            readme.write_text(
                "[inline](guide.md)\n![image](./guide.md)\n"
                "[reference]: /guide.md\n"
                "[protocol-relative](//github.com/leehack/genkit-llamadart)\n"
            )
            errors = check_pub_links(root, readme)
            self.assertEqual(len(errors), 4)
            self.assertTrue(all("absolute HTTPS" in error for error in errors))

    def test_pub_links_allow_https_and_in_page_anchors_and_ignore_code(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            readme = root / "README.md"
            readme.write_text(
                "# Guide\n[section](#guide)\n"
                "[file](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/README.md)\n"
                "![badge](https://example.invalid/badge.svg)\n"
                "[reference]: https://example.invalid/guide\n"
                "```markdown\n[example](relative.md)\n```\n"
            )
            self.assertEqual(check_pub_links(root, readme), [])

    def test_example_guides_are_checked(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "example/retrieval").mkdir(parents=True)
            guide = root / "example/retrieval/README.md"
            guide.write_text("[broken](missing.dart)\n")
            self.assertIn(guide, documents(root))
            self.assertEqual(len(check_links(root, guide)), 1)

    def test_links_resolve_relative_canonical_and_encoded_targets(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "doc").mkdir()
            (root / "doc/guide name.md").write_text("# Useful `API`\n# Useful `API`\n")
            readme = root / "README.md"
            readme.write_text(
                "[local](doc/guide%20name.md#useful-api)\n"
                "[canonical](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/"
                "doc/guide%20name.md#useful-api-1)\n"
                "[reference]: doc/guide%20name.md#useful-api\n"
                "[remote](https://example.invalid/does-not-exist)\n"
            )
            self.assertEqual(check_links(root, readme), [])
            readme.write_text("[bad](doc/missing.md)\n[bad](doc/guide%20name.md#missing)\n")
            errors = check_links(root, readme)
            self.assertEqual(len(errors), 2)
            self.assertIn("missing target", errors[0])
            self.assertIn("missing anchor", errors[1])

    def test_code_examples_do_not_create_links_or_anchors(self):
        markdown = "# Real\n```dart\n# Fake\n<a id=\"fake\">\n[bad](missing.md)\n```\n[good](#real)\n"
        self.assertEqual(destinations(markdown), ["#real"])
        self.assertEqual(anchors(markdown), {"real"})

    def test_bare_and_autolink_canonical_targets_are_checked(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            readme = root / "README.md"
            readme.write_text(
                "https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/missing.md.\n"
                "<https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/also-missing.md>\n"
            )
            self.assertEqual(len(check_links(root, readme)), 2)

    def test_same_document_anchor_is_validated(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            readme = root / "README.md"
            readme.write_text("# Real\n[good](#real)\n[bad](#missing)\n")
            self.assertEqual(len(check_links(root, readme)), 1)
