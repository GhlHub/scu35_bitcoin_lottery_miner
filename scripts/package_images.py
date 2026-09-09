#!/usr/bin/env python3
"""Patch BOTH Vivado bitstream and RCDO, then use the generated SpartanUP BIF.

Builds files only; never connects to a board or writes physical flash.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET
from verify_srec import verify

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "build/vivado/scu35_miner.runs/impl_1"
OUT = ROOT / "build/images"
VITIS = Path(os.environ.get("VITIS_ROOT", "/tools/Xilinx/2026.1/Vitis"))

def command(args, log, cwd):
    with (ROOT / "logs" / log).open("w") as output:
        subprocess.run(list(map(str, args)), cwd=cwd, stdout=output, stderr=subprocess.STDOUT, check=True)

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    mmi = ROOT / "build/scu35_miner.mmi"
    tree = ET.parse(mmi)
    cpu = tree.find("Processor")
    if cpu is None or cpu.attrib["InstPath"] != "design_1_i/microblaze_0":
        raise ValueError("Unexpected memory map processor")
    space = cpu.find("AddressSpace")
    if space is None or int(space.attrib["Begin"]) != 0 or int(space.attrib["End"]) != 16383:
        raise ValueError("Boot memory must be exactly 16 KiB")
    elf = ROOT / "build/bootloader/bootloader.elf"
    for suffix in ("bit", "rcdo"):
        command([VITIS / "bin/updatemem", "-force", "-meminfo", mmi, "-data", elf,
            "-bit", RUN / f"design_1_wrapper.{suffix}", "-proc", cpu.attrib["InstPath"],
            "-out", RUN / f"design_1_wrapper_bootloader.{suffix}"], f"package_{suffix}.log", ROOT / "logs")
    # Preserve the Vivado image structure and PLM; change only the PL payload.
    bif = (RUN / "design_1_wrapper.bif").read_text()
    if bif.count("file = design_1_wrapper.rcdo") != 1:
        raise ValueError("Unexpected Vivado BIF; review before packaging")
    (RUN / "design_1_wrapper_bootloader.bif").write_text(bif.replace("file = design_1_wrapper.rcdo", "file = design_1_wrapper_bootloader.rcdo"))
    command([VITIS / "bin/bootgen", "-arch", "spartanup", "-image", "design_1_wrapper_bootloader.bif",
        "-w", "-o", "design_1_wrapper_bootloader.pdi"], "bootgen.log", RUN)
    pdi = RUN / "design_1_wrapper_bootloader.pdi"
    srec = ROOT / "build/application/miner.srec"
    entry, loaded, records = verify(srec)
    if pdi.stat().st_size > 0x800000 or srec.stat().st_size > 0x800000:
        raise ValueError("Image exceeds its flash partition")
    shutil.copy2(pdi, OUT / "scu35_bootloader.pdi")
    shutil.copy2(srec, OUT / "miner.srec")
    shutil.copy2(elf, OUT / "bootloader.elf")
    shutil.copy2(ROOT / "build/application/miner.elf", OUT / "miner.elf")
    manifest = dict(board="SCU35", cpu_hz=50000000, application_entry=f"0x{entry:08x}",
        loaded_bytes=loaded, srec_records=records, hardware_tested=False, files={})
    for name, offset in [("scu35_bootloader.pdi", 0), ("miner.srec", 0x800000)]:
        data = (OUT / name).read_bytes()
        manifest["files"][name] = dict(flash_offset=f"0x{offset:08x}", size=len(data), sha256=hashlib.sha256(data).hexdigest())
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))

if __name__ == "__main__":
    main()
