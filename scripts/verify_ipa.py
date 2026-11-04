import hashlib
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import PurePosixPath, Path

path = Path(sys.argv[1])
with zipfile.ZipFile(path) as z:
    assert z.testzip() is None, "Uszkodzony ZIP"
    names = z.namelist()
    assert all(not PurePosixPath(n).is_absolute() and ".." not in PurePosixPath(n).parts for n in names)
    apps = [n for n in names if n.startswith("Payload/") and n.endswith(".app/Info.plist") and n.count("/") == 2]
    assert len(apps) == 1, "IPA musi zawierac jedna aplikacje"
    info = plistlib.loads(z.read(apps[0]))
    assert info["CFBundlePackageType"] == "APPL"
    assert info["CFBundleIdentifier"] == "app.synix.shaderlab3d"
    assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"]
    assert sorted(info["UIDeviceFamily"]) == [1, 2], "IPA musi obslugiwac iPhone i iPad"
    root = apps[0].removesuffix("Info.plist")
    exe_path = root + info["CFBundleExecutable"]
    data = z.read(exe_path)
    header = struct.unpack_from("<8I", data)
    assert header[0] == 0xfeedfacf, "Oczekiwany Mach-O 64-bit"
    assert header[1] == 0x0100000c, "Oczekiwany ARM64"
    assert header[3] == 2, "Oczekiwany plik wykonywalny"
    offset, platform, signed = 32, None, False
    for _ in range(header[4]):
        cmd, size = struct.unpack_from("<II", data, offset)
        assert size >= 8 and offset + size <= len(data)
        if cmd == 0x32:
            platform = struct.unpack_from("<I", data, offset + 8)[0]
        if cmd == 0x1d:
            signed = True
        offset += size
    assert platform == 2, "Plik musi byc zbudowany dla fizycznego iPhone, nie symulatora"
    assert not signed, "Oczekiwany niepodpisany IPA"
    assert root + "embedded.mobileprovision" not in names
    result = {"ipa": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "app": root, "bundle_id": info["CFBundleIdentifier"], "executable": exe_path, "architecture": "arm64", "platform": "iOS device", "device_family": info["UIDeviceFamily"], "minimum_ios": info["MinimumOSVersion"], "signed": signed, "zip_crc": "OK"}
    print(json.dumps(result, ensure_ascii=False, indent=2))
