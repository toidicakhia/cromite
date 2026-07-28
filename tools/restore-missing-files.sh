#!/bin/bash
# Restore missing Windows-specific files referenced by Win7 patches.
# Fetches from git HEAD or upstream Chromium googlesource when files are missing.
# Usage: restore-missing-files.sh <chromium-src-dir> <patches-dir> <version>
#   <patches-dir> can also be a file listing patch paths (one per line)

CHROMIUM_DIR=$1
PATCHES_DIR=$2
VERSION=$3

if [ -z "$CHROMIUM_DIR" ] || [ -z "$PATCHES_DIR" ] || [ -z "$VERSION" ]; then
    echo "Usage: $0 <chromium-src-dir> <patches-dir> <version>"
    exit 1
fi

cd "$CHROMIUM_DIR"

# Collect all unique files referenced in Win7 patches (--- a/ paths)
if [ -f "$PATCHES_DIR" ]; then
    # It's a file listing patch paths
    while IFS= read -r p; do
        [ -f "$p" ] && grep '^--- a/' "$p" | sed 's/.*--- a\///'
    done < "$PATCHES_DIR"
else
    grep -h '^--- a/' "$PATCHES_DIR"/0*.patch 2>/dev/null | sed 's/^--- a\///'
fi | sort -u > /tmp/all_patch_refs.txt

echo "Found $(wc -l < /tmp/all_patch_refs.txt) unique files referenced by Win7 patches"

# Phase 1: check what's missing
> /tmp/missing_list.txt
> /tmp/restore_failed.txt
MISSING_COUNT=0
while IFS= read -r file; do
    if [ ! -f "$file" ]; then
        echo "$MISSING_COUNT|$file" >> /tmp/missing_list.txt
        MISSING_COUNT=$((MISSING_COUNT + 1))
    fi
done < /tmp/all_patch_refs.txt

echo "Missing files: $MISSING_COUNT"
if [ "$MISSING_COUNT" -eq 0 ]; then
    echo "Nothing to restore."
    exit 0
fi

# Phase 2: try restoring from git HEAD (fast, no network)
> /tmp/still_missing.txt
RESTORED_COUNT=0
while IFS='|' read -r idx file; do
    mkdir -p "$(dirname "$file")"
    if git show HEAD:"$file" > "$file" 2>/dev/null && [ -s "$file" ]; then
        echo "  Restored (HEAD): $file"
        RESTORED_COUNT=$((RESTORED_COUNT + 1))
    else
        rm -f "$file"
        echo "$idx|$file" >> /tmp/still_missing.txt
    fi
done < /tmp/missing_list.txt

# Phase 3: try upstream Chromium googlesource for remaining files (parallel)
BRANCH=$(echo "$VERSION" | cut -d. -f3)
REMAINING=$(wc -l < /tmp/still_missing.txt 2>/dev/null || echo 0)

if [ "$REMAINING" -gt 0 ]; then
    echo "Trying upstream Chromium googlesource for $REMAINING files..."

    fetch_file() {
        local file="$1"
        local dir=$(dirname "$file")
        mkdir -p "$dir"

        # Try tag first (more precise), then branch-head
        for ref in "refs/tags/$VERSION" "refs/branch-heads/$BRANCH"; do
            local url="https://chromium.googlesource.com/chromium/src/+/$ref/$file?format=TEXT"
            local content
            content=$(curl -sSL --max-time 5 "$url" 2>/dev/null || true)
            if [ -n "$content" ] && ! echo "$content" | grep -qi "not found\|404\|not a valid object name\|no such"; then
                echo "$content" | base64 -d > "$file" 2>/dev/null || true
                if [ -f "$file" ] && [ -s "$file" ]; then
                    echo "  Restored (googlesource/$ref): $file"
                    return 0
                fi
            fi
        done
        return 1
    }
    export -f fetch_file
    export VERSION BRANCH

    > /tmp/restore_failed.txt
    while IFS='|' read -r idx file; do
        if fetch_file "$file"; then
            RESTORED_COUNT=$((RESTORED_COUNT + 1))
        else
            echo "$file" >> /tmp/restore_failed.txt
        fi
    done < /tmp/still_missing.txt
fi

FAILED_COUNT=$(wc -l < /tmp/restore_failed.txt 2>/dev/null || echo 0)
echo ""
echo "=== Restoration Summary ==="
echo "Total referenced files: $(wc -l < /tmp/all_patch_refs.txt)"
echo "Missing: $MISSING_COUNT"
echo "Restored: $RESTORED_COUNT"
echo "Failed: $FAILED_COUNT"

if [ "$FAILED_COUNT" -gt 0 ]; then
    echo "Files that could not be restored:"
    cat /tmp/restore_failed.txt
fi
