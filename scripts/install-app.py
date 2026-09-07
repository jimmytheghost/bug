#!/usr/bin/env python3
"""Install Bug at one stable path and clear stale grants before reapproval."""
import argparse
import datetime
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

BUNDLE_ID = "com.jimmyweber.bug"
TARGET = Path.home() / "Applications/Bug.app"
LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True)


def requirement(app):
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
    result = run("/usr/bin/codesign", "-d", "-r-", str(app))
    for line in (result.stdout + result.stderr).splitlines():
        if "designated => " in line:
            return line.split("designated => ", 1)[1]
    raise RuntimeError("Cannot identify the app's designated requirement.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--check", action="store_true", help="Read-only validation and installation plan")
    parser.add_argument("--repair-permissions", action="store_true",
                        help="Explicitly repair a stale grant even for the same build")
    args = parser.parse_args()
    source = args.app.expanduser().resolve()
    import plistlib
    with (source / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    if info.get("CFBundleIdentifier") != BUNDLE_ID:
        raise RuntimeError("Source is not Bug.")
    new_requirement = requirement(source)
    old_requirement = requirement(TARGET) if TARGET.exists() else None
    reset = args.repair_permissions or old_requirement != new_requirement
    print(f"Install Bug {info.get('CFBundleShortVersionString')} at {TARGET}")
    print("Reset only Bug ScreenCapture permission: " + ("yes; user must approve again" if reset else "no; identity unchanged"))
    if args.check:
        return
    running = subprocess.run(["/usr/bin/pgrep", "-x", "Bug"], capture_output=True)
    if running.returncode == 0:
        raise RuntimeError("Quit Bug before installing. Stop any active recording first.")
    if running.returncode != 1:
        raise RuntimeError("Could not determine whether Bug is running.")
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    # Stage and verify before touching the installed app or its permission.
    with tempfile.TemporaryDirectory(prefix=".Bug-install-", dir=TARGET.parent) as temporary:
        staged = Path(temporary) / "Bug.app"
        shutil.copytree(source, staged, symlinks=True)
        if requirement(staged) != new_requirement:
            raise RuntimeError("Staged app identity changed unexpectedly.")
        if reset:
            print(run("/usr/bin/tccutil", "reset", "ScreenCapture", BUNDLE_ID).stdout.strip())
        backup = None
        if TARGET.exists():
            backup_root = Path.home() / "Library/Application Support/Bug/BuildBackups"
            backup_root.mkdir(parents=True, exist_ok=True)
            backup = Path(tempfile.mkdtemp(prefix=datetime.datetime.now().strftime("%Y%m%d-%H%M%S-"),
                                          dir=backup_root)) / "Bug.app"
            run(LSREGISTER, "-u", str(TARGET))
            TARGET.rename(backup)
        try:
            staged.rename(TARGET)
        except Exception:
            if backup is not None:
                backup.rename(TARGET)
            raise
    # Older build folders are archives, not launch targets. Do not delete them.
    repository = Path(__file__).resolve().parent.parent
    for app in (repository / "dist").rglob("Bug.app"):
        subprocess.run([LSREGISTER, "-u", str(app)], capture_output=True)
    run(LSREGISTER, "-f", str(TARGET))
    print(f"Installed and verified: {TARGET}")
    print("Open this copy, click Record, approve Bug, then quit/reopen if macOS requests it.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Install stopped: {error}", file=sys.stderr)
        sys.exit(1)
