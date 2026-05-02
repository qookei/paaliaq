import argparse

from paaliaq.artix7.platform import PaaliaqPlatform
from paaliaq.artix7.top import PaaliaqTop


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--external-cpu", action="store_true")
    parser.add_argument("--allow-timing-fail", action="store_true")
    parser.add_argument("--target-clk", type=int, default=75)
    parser.add_argument("--boot-rom", type=str, default="../build/boot0.bin")
    parser.add_argument("--build-dir", type=str, default="build")

    args = parser.parse_args()

    platform = PaaliaqPlatform()

    with open("external/P65C816.v", "r") as f:
        platform.add_file("P65C816.v", f)

    platform.build(
        PaaliaqTop(
            external_cpu=args.external_cpu,
            target_clk=args.target_clk * 1e6,
            boot_rom_path=args.boot_rom,
        ),
        build_dir=args.build_dir,
    )
