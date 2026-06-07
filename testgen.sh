#!/usr/bin/env sh
set -e

ROOT="${1:-rm0_test}"

if [ -e "$ROOT" ]; then
    echo "Already exists: $ROOT" >&2
    exit 1
fi

echo "Generating test directory: $ROOT"

mkdir -p "$ROOT"

# ---------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------

# empty file
touch "$ROOT/empty"

# small text file
echo "sensitive data: password123" > "$ROOT/secrets.txt"

# binary file
dd if=/dev/urandom of="$ROOT/binary.bin" bs=1024 count=4 2>/dev/null

# large file
dd if=/dev/urandom of="$ROOT/large.bin" bs=1024 count=512 2>/dev/null

# hidden file
echo "hidden content" > "$ROOT/.hidden"

# file with spaces in name
echo "spaces in name" > "$ROOT/file with spaces.txt"

# file with long name
echo "long name" > "$ROOT/this_is_a_very_long_filename_that_tests_path_handling.txt"

# ---------------------------------------------------------------------------
# Nested directories
# ---------------------------------------------------------------------------

mkdir -p "$ROOT/subdir_a/nested_a"
mkdir -p "$ROOT/subdir_a/nested_b"
mkdir -p "$ROOT/subdir_b"

echo "subdir_a file" > "$ROOT/subdir_a/data.txt"
dd if=/dev/urandom of="$ROOT/subdir_a/random.bin" bs=512 count=1 2>/dev/null

echo "nested_a file" > "$ROOT/subdir_a/nested_a/data.txt"
touch "$ROOT/subdir_a/nested_a/empty"

echo "nested_b file 1" > "$ROOT/subdir_a/nested_b/one.txt"
echo "nested_b file 2" > "$ROOT/subdir_a/nested_b/two.txt"

echo "subdir_b file" > "$ROOT/subdir_b/data.txt"

# deeply nested
mkdir -p "$ROOT/deep/a/b/c"
echo "deep file" > "$ROOT/deep/a/b/c/data.txt"

# ---------------------------------------------------------------------------
# Symlinks
# ---------------------------------------------------------------------------

# valid symlink — points to existing file
ln -s "$ROOT/secrets.txt" "$ROOT/link_valid"

# dangling symlink — target does not exist
ln -s "/nonexistent/path/ghost.txt" "$ROOT/link_dangling"

# symlink inside subdir
ln -s "../secrets.txt" "$ROOT/subdir_a/link_relative"

# ---------------------------------------------------------------------------
# Named pipes (unix only)
# ---------------------------------------------------------------------------

if command -v mkfifo > /dev/null 2>&1; then
    mkfifo "$ROOT/named_pipe"
    mkfifo "$ROOT/subdir_b/named_pipe"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Files:       $(find "$ROOT" -type f | wc -l | tr -d ' ')"
echo "Directories: $(find "$ROOT" -type d | wc -l | tr -d ' ')"
echo "Symlinks:    $(find "$ROOT" -type l | wc -l | tr -d ' ')"
echo "Pipes:       $(find "$ROOT" -type p | wc -l | tr -d ' ')"
echo ""
echo "Run: rm0 $ROOT"
