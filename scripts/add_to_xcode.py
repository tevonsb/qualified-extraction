#!/usr/bin/env python3
"""
Automatically add Swift files to Xcode project
"""

import sys
import os
import uuid
import re

def generate_uuid():
    """Generate a unique 24-character hex ID like Xcode uses"""
    return ''.join(format(x, '02X') for x in os.urandom(12))

def add_files_to_xcode(project_path, files_to_add):
    """Add Swift files to an Xcode project"""

    pbxproj_path = os.path.join(project_path, 'project.pbxproj')

    if not os.path.exists(pbxproj_path):
        print(f"Error: {pbxproj_path} not found")
        return False

    with open(pbxproj_path, 'r') as f:
        content = f.read()

    # Find the main group and sources build phase
    main_group_match = re.search(r'/\* QualifiedApp \*/.*?isa = PBXGroup;.*?children = \((.*?)\);', content, re.DOTALL)
    if not main_group_match:
        print("Error: Could not find QualifiedApp group")
        return False

    sources_match = re.search(r'/\* Sources \*/.*?isa = PBXSourcesBuildPhase;.*?files = \((.*?)\);', content, re.DOTALL)
    if not sources_match:
        print("Error: Could not find Sources build phase")
        return False

    file_refs = {}
    build_files = {}

    for file_path in files_to_add:
        if not os.path.exists(file_path):
            print(f"Warning: {file_path} does not exist, skipping")
            continue

        filename = os.path.basename(file_path)

        # Check if file already exists in project
        if filename in content:
            print(f"Skipping {filename} (already in project)")
            continue

        # Generate UUIDs
        fileref_uuid = generate_uuid()
        buildfile_uuid = generate_uuid()

        # Create PBXFileReference entry
        file_ref_entry = f"\t\t{fileref_uuid} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = \"<group>\"; }};\n"

        # Create PBXBuildFile entry
        build_file_entry = f"\t\t{buildfile_uuid} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {fileref_uuid} /* {filename} */; }};\n"

        file_refs[filename] = (fileref_uuid, file_ref_entry)
        build_files[filename] = (buildfile_uuid, build_file_entry)

    if not file_refs:
        print("No files to add")
        return True

    # Add PBXFileReference entries
    pbx_file_ref_section = re.search(r'/\* Begin PBXFileReference section \*/(.*?)/\* End PBXFileReference section \*/', content, re.DOTALL)
    if pbx_file_ref_section:
        insertion_point = pbx_file_ref_section.end(1)
        for filename, (uuid, entry) in file_refs.items():
            content = content[:insertion_point] + entry + content[insertion_point:]
            insertion_point += len(entry)
            print(f"Added PBXFileReference for {filename}")

    # Add PBXBuildFile entries
    pbx_build_file_section = re.search(r'/\* Begin PBXBuildFile section \*/(.*?)/\* End PBXBuildFile section \*/', content, re.DOTALL)
    if pbx_build_file_section:
        insertion_point = pbx_build_file_section.end(1)
        for filename, (uuid, entry) in build_files.items():
            content = content[:insertion_point] + entry + content[insertion_point:]
            insertion_point += len(entry)
            print(f"Added PBXBuildFile for {filename}")

    # Add to main group children
    main_group_match = re.search(r'(/\* QualifiedApp \*/.*?isa = PBXGroup;.*?children = \()(.*?)(\);)', content, re.DOTALL)
    if main_group_match:
        children_content = main_group_match.group(2)
        insertion_point = main_group_match.end(2)

        for filename, (uuid, _) in file_refs.items():
            child_entry = f"\t\t\t\t{uuid} /* {filename} */,\n"
            content = content[:insertion_point] + child_entry + content[insertion_point:]
            insertion_point += len(child_entry)
            print(f"Added {filename} to group children")

    # Add to Sources build phase
    sources_match = re.search(r'(/\* Sources \*/.*?isa = PBXSourcesBuildPhase;.*?files = \()(.*?)(\);)', content, re.DOTALL)
    if sources_match:
        insertion_point = sources_match.end(2)

        for filename, (build_uuid, _) in build_files.items():
            source_entry = f"\t\t\t\t{build_uuid} /* {filename} in Sources */,\n"
            content = content[:insertion_point] + source_entry + content[insertion_point:]
            insertion_point += len(source_entry)
            print(f"Added {filename} to Sources phase")

    # Write back
    with open(pbxproj_path, 'w') as f:
        f.write(content)

    print("\nSuccessfully updated project file!")
    return True

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: add_to_xcode.py <project_path> <file1.swift> [file2.swift] ...")
        sys.exit(1)

    project_path = sys.argv[1]
    files = sys.argv[2:]

    success = add_files_to_xcode(project_path, files)
    sys.exit(0 if success else 1)
