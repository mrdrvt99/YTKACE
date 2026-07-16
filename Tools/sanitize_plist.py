#!/usr/bin/env python3

import pathlib
import plistlib
import sys


def should_remove(name: str) -> bool:
    lowered = name.lower()
    return lowered == "ytk" or "ytkplus" in lowered or "ytkiller" in lowered


def clean_icons(root: dict) -> None:
    for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
        icons = root.get(key)
        if not isinstance(icons, dict):
            continue
        alternate = icons.get("CFBundleAlternateIcons")
        if not isinstance(alternate, dict):
            continue
        for name in list(alternate):
            if should_remove(str(name)):
                del alternate[name]


def main() -> int:
    if len(sys.argv) != 2:
        return 2
    path = pathlib.Path(sys.argv[1])
    with path.open("rb") as handle:
        root = plistlib.load(handle)
    clean_icons(root)
    with path.open("wb") as handle:
        plistlib.dump(root, handle, fmt=plistlib.FMT_BINARY, sort_keys=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
