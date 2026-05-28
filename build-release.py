
"""
Build a release zip.

Before doing so, it performs the following checks:
- Ensure the logging is turned off in raconfig.
- Ensure that the crystal sprites aren't deactivated for Gen1
- Check I didn't leave any stray checksum identifications.

And performs the following tasks:
- Synchronize the Aseprite scripts
- Pack the Aseprite plugin into a zip

All checks return a list of string error messages or an empty list. At the
end, all errors are printed or the zip is built.
"""

import os
import shutil
import subprocess
import zipfile

def get_version():
    with open("luascripts/ramanimator/raconfig.lua") as inf:
        lines = inf.readlines()

    for line in lines:
        if line.startswith("raconfig.version"):
            return line.split()[-1][1:-1]

    raise Exception("Could not read version number from raconfig")

def check_logging_off():
    with open("luascripts/ramanimator/raconfig.lua") as inf:
        lines = inf.readlines()

    for line in lines:
        if line.startswith("raconfig.logLevel"):
            if not line.strip().endswith("0"):
                return ["Logging is not turned off in raconfig."]
            else:
                return []

    return ["Could not find the line for the logLevel in raconfig."]

def check_gen1_anims():
    """
    When creating the gen 1 sprite showcase, one needs to deactivate the
    Crystal sprites for gen1. Check that change was reverted.
    """

    with open("luascripts/ramanimator/pokemon.lua") as inf:
        lines = inf.readlines()

    for i_line, line in enumerate(lines):
        if line.strip().startswith('if targetSprites == "gen1" then'):
            # Check all lines up to the }
            for line in lines[i_line + 2:]:
                if "}" in line:
                    return []
                if line.strip().startswith("--") and "crystal" in line:
                    return ["In pokemon.lua, it seems the Crystal sprites are deactivated for gen1."]

    return ["Could not find the gen1 targetSprites in pokemon.lua."]

def check_stray_checksum_identifiers():
    """
    Checks we don't leave any game configurations lying around. Just
    having random hacks set up wouldn't be problematic, but they likely
    use paths to custom hook / animation files which wouldn't be
    included.

    Technically, this one is only a problem if it has staged changes...
    """
    with open("luascripts/ramanimator/identify-checksum.lua") as inf:
        lines = inf.readlines()

    if len(lines) > 25:
        return ["It seems there are some checksum identifications left in identify-checksum.lua"]

    return []

if __name__ == '__main__':
    errors = []
    errors.extend(check_logging_off())
    errors.extend(check_gen1_anims())
    errors.extend(check_stray_checksum_identifiers())

    if len(errors) > 0:
        for err in errors:
            print(err)

        exit(1)

    # Everything looks fine, start the actual build
    # Copy Aseprite files over
    asedir = "~/.config/aseprite/extensions/ramanimator/"
    asedir = os.path.expanduser(asedir)
    asedest = "aseextension"

    if os.path.isdir(asedir):
        for entry in os.listdir(asedir):
            if entry.startswith("__"):
                continue

            src_path = os.path.join(asedir, entry)
            if os.path.isfile(src_path):
                shutil.copy2(src_path, asedest)
    else:
        print(f"The Aseprite extension does not seem to be installed, so assume all Aseprite files are up-to-date.")

    # Zip the Aseprite extension
    asedest = os.path.abspath(asedest)
    asezip = "RAManimator.aseprite-extension"
    with zipfile.ZipFile(asezip, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(asedest):
            for f in files:
                full_path = os.path.join(root, f)
                # store files with a relative path inside the zip
                rel_path = os.path.relpath(full_path, start=asedest)
                zf.write(full_path, arcname=rel_path)

    version = get_version()

    # git archive --format=zip --prefix=RAManimator/ -o zipname.zip HEAD
    prefix = "RAManimator/"
    zip_path = f"RAManimator-{version}.zip"
    cmd = [
        "git",
        "archive",
        "--format=zip",
        f"--prefix={prefix}",
        f"--add-file={asezip}",
        "-o",
        zip_path,
        "HEAD",
    ]

    print(" ".join(cmd))

    result = subprocess.run(cmd, check=False, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"git archive failed: {result.stderr.strip()}")
