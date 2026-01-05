#!/bin/bash

# Script to automatically add Swift files to Xcode project
# Usage: ./add_files_to_xcode.sh [file1.swift] [file2.swift] ...

set -e

PROJECT_DIR="/Users/tevonstrand-brown/Desktop/qualified-extraction/QualifiedApp"
PROJECT_FILE="$PROJECT_DIR/QualifiedApp.xcodeproj/project.pbxproj"

if [ ! -f "$PROJECT_FILE" ]; then
    echo "Error: Project file not found at $PROJECT_FILE"
    exit 1
fi

# Install xcodeproj gem if not present (for Ruby-based manipulation)
if ! command -v xcodeproj &> /dev/null; then
    echo "Installing xcodeproj gem..."
    gem install xcodeproj --user-install
fi

# Create Ruby script to add files
cat > /tmp/add_xcode_files.rb << 'RUBY'
require 'xcodeproj'

project_path = ARGV[0]
files_to_add = ARGV[1..-1]

project = Xcodeproj::Project.open(project_path)
target = project.targets.first
group = project.main_group.find_subpath('QualifiedApp', true)

files_to_add.each do |file_path|
  next unless File.exist?(file_path)
  next if group.files.any? { |f| f.path == File.basename(file_path) }

  file_ref = group.new_file(file_path)
  target.add_file_references([file_ref])
  puts "Added: #{File.basename(file_path)}"
end

project.save
RUBY

# Run the Ruby script
ruby /tmp/add_xcode_files.rb "$PROJECT_DIR/QualifiedApp.xcodeproj" "$@"

echo "Files added to Xcode project successfully!"
