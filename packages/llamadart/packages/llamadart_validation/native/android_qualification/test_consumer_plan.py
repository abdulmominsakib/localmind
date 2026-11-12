"""Model-free checks for release build identity and prospective device plans."""
import base64
from pathlib import Path
import unittest

import prepare_consumer


class ConsumerPlanTest(unittest.TestCase):
    def test_both_builds_share_profile_and_source_defines(self):
        for profile in ("full", "compact"):
            plan = prepare_consumer.operator_plan(profile, "a" * 40, "b" * 40, Path("/stage"))
            flutter, gradle = [entry["argv"] for entry in plan["commands"]]
            definitions = [arg.removeprefix("--dart-define=") for arg in flutter
                           if arg.startswith("--dart-define=")]
            encoded = next(arg.removeprefix("-Pdart-defines=") for arg in gradle
                           if arg.startswith("-Pdart-defines="))
            self.assertEqual(definitions, [base64.b64decode(value).decode() for value in encoded.split(",")])
            self.assertIn("LLAMADART_ANDROID_CPU_PROFILE=" + profile, definitions)
            self.assertIn("--release", flutter)
            self.assertEqual([row["device_class"] for row in plan["run_drafts"]], ["old", "modern"])
            self.assertTrue(all(row["status"] == "NOT_RUN" for row in plan["run_drafts"]))
            self.assertFalse(plan["qualification"])
            self.assertEqual(plan["consumer_dependency_requirements"]["integration_test"],
                             {"sdk": "flutter", "section": "dependencies",
                              "forbidden_section": "dev_dependencies"})
            self.assertTrue(all(row["app_apk_sha256"] is None for row in plan["run_drafts"]))


if __name__ == "__main__":
    unittest.main()
