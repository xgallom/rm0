# rm0

A secure file and directory eraser. Overwrites file contents with multiple passes of random data before deletion,
making recovery significantly harder on magnetic storage.

## What it does

For each **file**:
1. Overwrites contents with random data
2. Overwrites with `0xFF`
3. Overwrites with random data again
4. Syncs to disk after each pass
5. Truncates to zero
6. Renames to a random name
7. Deletes

For each **directory**: recurses into all contents, erases everything, renames, then removes the empty directory.

**Symlinks, named pipes, and sockets** — the filesystem entry is renamed and removed. Symlinks are never followed.

## Limitations

**SSDs** — wear-leveling means overwrites may be written to different physical cells than the original data.
Software-level overwriting cannot guarantee erasure on solid-state storage. For SSDs, full disk encryption at rest is 
the only reliable protection.

**Journaling filesystems** — filesystems like ext4 and NTFS may retain metadata about files in their journal after
deletion. rm0 cannot erase journal entries.

For strong guarantees on modern hardware, use full disk encryption from the start rather than relying solely on secure
deletion.

## Installation

### Prebuilt binaries

Download from the [releases page](https://github.com/xgallom/rm0/releases):

| Platform            | Binary                    |
|---------------------|---------------------------|
| Linux x86_64        | `rm0-linux-x86_64`        |
| Windows x86_64      | `rm0-windows-x86_64.exe`  |
| macOS Apple Silicon | `rm0-macos-aarch64`       |

### Build from source

Requires [Zig 0.15.2](https://ziglang.org/download/).

```sh
git clone https://github.com/xgallom/rm0
cd rm0
zig build --release=fast
```

Binary is at `zig-out/bin/rm0`.

## Usage

```
rm0 [-h | --help] [...{path}]

Securely erase files and directories by overwriting contents
with random data before deletion.

Arguments:
  {path}         : one or more files or directories to erase
  -h, --help     : display this help

Notes:
  Directories are erased recursively.
  Symlinks are removed without following them.
  On SSDs, overwriting does not guarantee data erasure due to
  wear-leveling. Use full disk encryption for stronger guarantees.
```

### Examples

```sh
# Erase a single file
rm0 secrets.txt

# Erase multiple files
rm0 secrets.txt private.key notes.txt

# Erase a directory recursively
rm0 private/

# Erase multiple paths
rm0 secrets.txt private/ cache/
```

## License

[MIT](LICENSE.md)
