import tempfile
import unittest
from pathlib import Path

from split_rspec_specs import DEFAULT_WEIGHT_SECONDS, load_weights, split_specs


class SplitRSpecSpecsTest(unittest.TestCase):
    def test_weighted_split_is_deterministic_and_keeps_each_spec_once(self):
        specs = ["spec/c.rb", "spec/a.rb", "spec/d.rb", "spec/b.rb", "spec/new.rb"]
        weights = {"spec/a.rb": 8, "spec/b.rb": 7, "spec/c.rb": 2, "spec/d.rb": 1}

        first = split_specs(specs, 2, weights)
        second = split_specs(specs, 2, weights)

        self.assertEqual(first, second)
        self.assertEqual(sorted(specs), sorted(spec for bucket in first for spec in bucket))
        totals = [sum(weights.get(spec, DEFAULT_WEIGHT_SECONDS) for spec in bucket) for bucket in first]
        self.assertEqual(19.0, sum(totals))
        self.assertEqual(1, sum(spec == "spec/new.rb" for bucket in first for spec in bucket))

    def test_missing_timing_file_uses_historical_round_robin(self):
        specs = [f"spec/{letter}.rb" for letter in "abcd"]

        with tempfile.TemporaryDirectory() as directory:
            timings = Path(directory) / "missing.json"
            weights = load_weights(timings)

        self.assertIsNone(weights)
        self.assertEqual(
            [["spec/a.rb", "spec/c.rb"], ["spec/b.rb", "spec/d.rb"]],
            split_specs(specs, 2, weights),
        )

    def test_unreadable_timing_file_uses_historical_round_robin(self):
        with tempfile.TemporaryDirectory() as directory:
            timings = Path(directory) / "timings.json"
            timings.write_text("{invalid json", encoding="utf-8")

            self.assertIsNone(load_weights(timings))


if __name__ == "__main__":
    unittest.main()
