#!/usr/bin/env python3
"""Export implementation ABIs, or verify that delivered exports match a fresh offline build."""

import argparse
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if an exported ABI is stale")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    subprocess.run(["forge", "build", "--offline"], cwd=root, check=True)
    for contract in ("TipJarToken", "TipVault"):
        artifact = root / "out" / f"{contract}.sol" / f"{contract}.json"
        abi = json.loads(artifact.read_text())["abi"]
        text = json.dumps(abi, indent=2) + "\n"
        target = root / "docs" / "abi" / f"{contract}.json"
        if args.check:
            if not target.exists() or target.read_text() != text:
                raise SystemExit(f"Stale ABI: {target.relative_to(root)}")
            print(f"Verified {target.relative_to(root)}")
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
            print(f"Exported {target.relative_to(root)}")


if __name__ == "__main__":
    main()
