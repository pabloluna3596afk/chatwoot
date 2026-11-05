#!/usr/bin/env python3
"""Split RSpec files by recorded runtime, with the historical split as fallback."""

import argparse
import json
import math
import sys
from collections import defaultdict
from pathlib import Path


DEFAULT_WEIGHT_SECONDS = 1.0


def load_weights(path):
    """Load per-file weights. Invalid or missing data returns None for fallback."""
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        weights = data["specs"]
        if not isinstance(weights, dict):
            return None
        parsed = {}
        for spec, weight in weights.items():
            if not isinstance(spec, str) or not isinstance(weight, (int, float)):
                return None
            if not math.isfinite(weight) or weight <= 0:
                return None
            parsed[spec.removeprefix("./")] = float(weight)
        return parsed
    except (OSError, ValueError, KeyError, TypeError):
        return None


def split_specs(specs, slice_count, weights):
    """Return deterministic slice assignments, preserving the old split if needed."""
    specs = sorted(spec.removeprefix("./") for spec in specs)
    if weights is None:
        return [[spec for index, spec in enumerate(specs) if index % slice_count == slot]
                for slot in range(slice_count)]

    slices = [[] for _ in range(slice_count)]
    totals = [0.0] * slice_count
    # Stable path tie-break makes every run produce the same assignments.
    ordered = sorted(specs, key=lambda spec: (-weights.get(spec, DEFAULT_WEIGHT_SECONDS), spec))
    for spec in ordered:
        slot = min(range(slice_count), key=lambda index: (totals[index], index))
        slices[slot].append(spec)
        totals[slot] += weights.get(spec, DEFAULT_WEIGHT_SECONDS)
    return [sorted(bucket) for bucket in slices]


def aggregate_results(result_paths):
    """Aggregate RSpec JSON example runtimes into per-spec elapsed seconds."""
    totals = defaultdict(float)
    for result_path in result_paths:
        result = json.loads(Path(result_path).read_text(encoding="utf-8"))
        for example in result["examples"]:
            file_path = example["file_path"].removeprefix("./")
            runtime = float(example["run_time"])
            if runtime > 0:
                totals[file_path] += runtime
    return dict(sorted(totals.items()))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--slices", type=int, default=1)
    parser.add_argument("--timings", default=".github/rspec_spec_timings.json")
    parser.add_argument("--spec-list", help="Read one spec path per line from this file")
    parser.add_argument("--output", help="Write slice assignments to this UTF-8 TSV file")
    parser.add_argument("--write-timings", help="Build a timing map from RSpec JSON results")
    parser.add_argument("--results", nargs="*", default=[])
    parser.add_argument("specs", nargs="*")
    args = parser.parse_args()

    if args.slices < 1:
        parser.error("--slices must be at least 1")
    if args.write_timings:
        timings = aggregate_results(args.results)
        if args.spec_list:
            current_specs = {
                spec.removeprefix("./")
                for spec in Path(args.spec_list).read_text(encoding="utf-8").splitlines()
            }
            timings = {spec: seconds for spec, seconds in timings.items() if spec in current_specs}
            missing_specs = current_specs - timings.keys()
            print(
                f"Recorded {len(timings)} spec timings; {len(missing_specs)} specs will use the default weight",
                file=sys.stderr,
            )
        Path(args.write_timings).write_text(
            json.dumps({"default_weight_seconds": DEFAULT_WEIGHT_SECONDS, "specs": timings}, indent=2) + "\n",
            encoding="utf-8",
        )
        return

    specs = Path(args.spec_list).read_text(encoding="utf-8").splitlines() if args.spec_list else args.specs
    weights = load_weights(args.timings)
    if weights is None:
        print(f"::warning::Could not read {args.timings}; using the historical round-robin split", file=sys.stderr)
    buckets = split_specs(specs, args.slices, weights)
    flattened = [spec for bucket in buckets for spec in bucket]
    if len(flattened) != len(specs) or set(flattened) != {s.removeprefix("./") for s in specs}:
        raise SystemExit("Slice assignment did not preserve every spec exactly once")

    assignments = []
    for index, bucket in enumerate(buckets):
        total = sum((weights or {}).get(spec, DEFAULT_WEIGHT_SECONDS) for spec in bucket)
        print(f"Slice {index}: {total:.3f}s across {len(bucket)} specs", file=sys.stderr)
        for spec in bucket:
            weight = (weights or {}).get(spec, DEFAULT_WEIGHT_SECONDS)
            assignments.append(f"{index}\t{weight:.3f}\t{spec}")
    output = "\n".join(assignments) + ("\n" if assignments else "")
    if args.output:
        Path(args.output).write_text(output, encoding="utf-8")
    else:
        print(output, end="")
    print(f"Verified {len(flattened)} specs assigned exactly once", file=sys.stderr)


if __name__ == "__main__":
    main()
