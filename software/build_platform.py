"""Create the standalone MicroBlaze BSP from this project's hardware handoff."""
from pathlib import Path
import vitis

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "build/vitis"

def main():
    client = vitis.create_client()
    try:
        client.set_workspace(str(WORK))
        try:
            platform = client.get_component(name="scu35_platform")
        except Exception:
            platform = client.create_platform_component(
                name="scu35_platform", hw_design=str(ROOT / "build/scu35_miner.xsa"),
                os="standalone", cpu="microblaze_0", domain_name="standalone_microblaze_0")
        else:
            platform.update_hw(hw_design=str(ROOT / "build/scu35_miner.xsa"))
        platform.build()
    finally:
        vitis.dispose()

if __name__ == "__main__":
    main()
