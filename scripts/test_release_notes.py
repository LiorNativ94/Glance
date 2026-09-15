import unittest

from release_notes import release_notes


class ReleaseNotesTests(unittest.TestCase):
    def test_extracts_only_the_requested_version(self):
        notes = release_notes("# Changelog\n\n## v1.2.4\n\n- Fixed bars.\n- Improved controls.\n\n## v1.2\n\n- Old change.\n- Older change.\n", "v1.2.4")
        self.assertIn("- Fixed bars.\n- Improved controls.", notes)
        self.assertNotIn("Old change", notes)
        self.assertIn("Glance-1.2.4-universal.dmg", notes)

    def test_rejects_missing_or_duplicate_version(self):
        for source in ["## v1.2\n- One.\n- Two.\n", "## v1.2.4\n- One.\n- Two.\n## v1.2.4\n- Three.\n- Four.\n"]:
            with self.subTest(source=source), self.assertRaises(ValueError):
                release_notes(source, "v1.2.4")

    def test_rejects_empty_or_unstructured_notes(self):
        for body in ["", "- One.\n", "- \n- Two.\n", "Some prose.\n- Two.\n", "- One.\n- Two.\n  Wrapped line.\n", "\n".join(f"- Change {i}." for i in range(5))]:
            with self.subTest(body=body), self.assertRaises(ValueError):
                release_notes("## v1.2.4\n" + body, "v1.2.4")

    def test_accepts_four_bullets_and_two_part_versions(self):
        notes = release_notes("## v1.3\n" + "\n".join(f"- Change {i}." for i in range(4)), "v1.3")
        self.assertIn("Glance-1.3-universal.dmg", notes)

    def test_rebuild_reads_updated_entry(self):
        before = "## v1.2.4\n- One.\n- Two.\n"
        after = before.replace("Two.", "New fix.")
        self.assertIn("New fix.", release_notes(after, "v1.2.4"))
        self.assertNotEqual(release_notes(before, "v1.2.4"), release_notes(after, "v1.2.4"))

    def test_rejects_invalid_tags(self):
        for tag in ["1.2.4", "v01.2.4", "v1.2.4-beta", "v1.2.4\n"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release_notes("", tag)


if __name__ == "__main__":
    unittest.main()
