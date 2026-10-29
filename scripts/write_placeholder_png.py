#!/usr/bin/env python3
"""Write a tiny valid PNG so the Xcode catalog compiles before Muse Image returns."""
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def png(width: int, height: int, rgb: tuple[int, int, int]) -> bytes:
    raw = b"".join(b"\x00" + (bytes(rgb) * width) for _ in range(height))
    return b"".join(
        [
            b"\x89PNG\r\n\x1a\n",
            chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)),
            chunk(b"IDAT", zlib.compress(raw, 9)),
            chunk(b"IEND", b""),
        ]
    )


def maybe(path: Path, rgb: tuple[int, int, int], size: int = 64) -> None:
    if path.exists() and path.stat().st_size > 800:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png(size, size, rgb))
    print("placeholder", path)


def main() -> None:
    assets = ROOT / "samdevna" / "Assets.xcassets"
    maybe(assets / "AppIcon.appiconset" / "AppIcon.png", (255, 176, 32), 1024)
    maybe(assets / "DemoHome.imageset" / "DemoHome.png", (196, 92, 38), 512)
    maybe(assets / "DemoMachine.imageset" / "DemoMachine.png", (27, 39, 68), 512)


if __name__ == "__main__":
    main()
