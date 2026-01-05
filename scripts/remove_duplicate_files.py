#!/usr/bin/env python3
"""Remove duplicate file references from Xcode project"""

import re
import sys


def remove_duplicates(project_path):
    with open(project_path, "r") as f:
        content = f.read()

    # Remove the duplicate entries I added (7B67... and F5C3... and BDCD... prefixed UUIDs)
    uuids_to_remove = [
        "7B67567376070B99D4384281",  # DatabaseService
        "F5C360F5CEF806BB37E3E855",  # MessagesDetailSheet
        "F7571CCCEB5A94E45B5FBCC4",  # MessagesDetailSheet (another)
        "BDCDD0EF51D22E947C3431B0",  # DatabaseService (another)
    ]

    for uuid in uuids_to_remove:
        # Remove PBXBuildFile entries
        content = re.sub(rf"\t\t{uuid} /\*.*?\*/.*?\n", "", content)
        # Remove PBXFileReference entries
        content = re.sub(rf"\t\t{uuid} /\*.*?\*/ = \{{[^}}]*\}};\n", "", content)
        # Remove from children arrays
        content = re.sub(rf"\t\t\t\t{uuid} /\*.*?\*/,\n", "", content)

    with open(project_path, "w") as f:
        f.write(content)

    print("Removed duplicate references")


if __name__ == "__main__":
    project_path = (
        sys.argv[1] if len(sys.argv) > 1 else "QualifiedApp.xcodeproj/project.pbxproj"
    )
    remove_duplicates(project_path)
