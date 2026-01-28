#!/bin/bash

# Check if version part is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <major|minor|patch|show> [operation]"
    echo "Examples:"
    echo "  $0 show       # Show current version and exit"
    echo "  $0 patch      # Increment patch version (default)"
    echo "  $0 minor      # Increment minor version (default)"
    echo "  $0 major      # Increment major version (default)"
    echo "  $0 patch -    # Decrement patch version"
    echo "  $0 minor -    # Decrement minor version"
    echo "  $0 major -    # Decrement major version"
    exit 1
fi

PART="$1"

# Default to +1 if no operation specified, use -1 if second arg is "-"
if [ "$2" = "-" ]; then
    OPERATION="-1"
else
    OPERATION="+1"
fi

# Get current version from Makefile
if [ ! -f "Makefile" ]; then
    echo "Error: Makefile not found!"
    exit 1
fi

# Extract current version or set default
CURRENT_VERSION=$(grep '^APP_VERSION = ' Makefile | cut -d ' ' -f 3)
if [ -z "$CURRENT_VERSION" ] || [ "$CURRENT_VERSION" = "" ]; then
    CURRENT_VERSION="v0.0.0"
    echo "No version found, using default: $CURRENT_VERSION"
fi

# ----------------------------
# Show current version and exit (read-only)
# ----------------------------
if [ "$PART" = "current" ] || [ "$PART" = "show" ]; then
    echo "Current version: ${CURRENT_VERSION}"
    exit 0
fi

# ----------------------------
# Parse version parts + presence flags
# ----------------------------
RAW_VERSION="${CURRENT_VERSION#v}"
BASE_VERSION="${RAW_VERSION%%-*}"   # strip suffix for counting parts

ENV_SUFFIX=""
if [[ "$CURRENT_VERSION" == *"-"* ]]; then
    ENV_SUFFIX="${CURRENT_VERSION#*-}"
fi

IFS='.' read -r -a VERSION_PARTS <<< "$BASE_VERSION"

HAS_MINOR=0
HAS_PATCH=0
[ ${#VERSION_PARTS[@]} -ge 2 ] && HAS_MINOR=1
[ ${#VERSION_PARTS[@]} -ge 3 ] && HAS_PATCH=1

MAJOR=${VERSION_PARTS[0]:-0}
MINOR=${VERSION_PARTS[1]:-0}
PATCH=${VERSION_PARTS[2]:-0}

build_version() {
    local major="$1" minor="$2" patch="$3"

    local v="v${major}"
    if [ "$HAS_MINOR" -eq 1 ] || [ "$HAS_PATCH" -eq 1 ]; then
        v="${v}.${minor}"
    fi
    if [ "$HAS_PATCH" -eq 1 ]; then
        v="${v}.${patch}"
    fi

    echo "${v}${ENV_SUFFIX:+-$ENV_SUFFIX}"
}

# ----------------------------
# Calculate new version
# Rules:
# - patch bump retains major+minor, changes patch (creates patch if missing)
# - minor bump retains major, changes minor, and drops patch (reset to 0 if patch existed; omit if it didn't)
# - major bump changes major, resets minor/patch to 0 only if they existed
# ----------------------------
case "$PART" in
    major)
        if [ "$OPERATION" = "+1" ]; then
            NEW_MAJOR=$((MAJOR + 1))
        else
            NEW_MAJOR=$((MAJOR - 1))
        fi

        if [ $NEW_MAJOR -lt 0 ]; then
            echo "Error: Major version cannot be negative"
            exit 1
        fi

        # Reset lower parts (only if they existed)
        NEW_MINOR=0
        NEW_PATCH=0
        NEW_VERSION="$(build_version "$NEW_MAJOR" "$NEW_MINOR" "$NEW_PATCH")"
        ;;

    minor)
        if [ "$OPERATION" = "+1" ]; then
            NEW_MINOR=$((MINOR + 1))
        else
            NEW_MINOR=$((MINOR - 1))
        fi

        # If minor wasn't present and we're incrementing, create it
        if [ "$HAS_MINOR" -eq 0 ] && [ "$OPERATION" = "+1" ]; then
            HAS_MINOR=1
            NEW_MINOR=1
        fi

        if [ $NEW_MINOR -lt 0 ]; then
            echo "Error: Minor version cannot be negative"
            exit 1
        fi

        # Drop patch on minor bump:
        # - if patch existed, keep shape but reset patch to 0
        # - if patch didn't exist, keep it omitted
        if [ "$HAS_PATCH" -eq 1 ]; then
            NEW_VERSION="$(build_version "$MAJOR" "$NEW_MINOR" "0")"
        else
            NEW_VERSION="$(build_version "$MAJOR" "$NEW_MINOR" "$PATCH")"  # PATCH ignored because HAS_PATCH=0
        fi
        ;;

    patch)
        # Create patch if missing (patch bump implies minor+patch exist)
        if [ "$HAS_PATCH" -eq 0 ]; then
            HAS_PATCH=1
            HAS_MINOR=1
            MINOR=${MINOR:-0}
            PATCH=0
        fi

        if [ "$OPERATION" = "+1" ]; then
            NEW_PATCH=$((PATCH + 1))
            NEW_MAJOR=$MAJOR
            NEW_MINOR=$MINOR
        else
            NEW_PATCH=$((PATCH - 1))
            NEW_MAJOR=$MAJOR
            NEW_MINOR=$MINOR

            # Borrow if patch goes negative
            if [ $NEW_PATCH -lt 0 ]; then
                if [ $MINOR -gt 0 ]; then
                    NEW_MINOR=$((MINOR - 1))
                    NEW_PATCH=0
                elif [ $MAJOR -gt 0 ]; then
                    NEW_MAJOR=$((MAJOR - 1))
                    NEW_MINOR=0
                    NEW_PATCH=0
                else
                    echo "Error: Patch version cannot be negative when major and minor are 0"
                    exit 1
                fi
            fi
        fi

        NEW_VERSION="$(build_version "$NEW_MAJOR" "$NEW_MINOR" "$NEW_PATCH")"
        ;;

    *)
        echo "Error: Invalid part. Use 'major', 'minor', 'patch', 'current', or 'show'"
        exit 1
        ;;
esac

echo "Current version: ${CURRENT_VERSION}"
echo "New version:     ${NEW_VERSION}"

# Update Makefile
if grep -q "^APP_VERSION =" Makefile; then
    sed -i '' "s/^APP_VERSION = .*/APP_VERSION = ${NEW_VERSION}/" Makefile
else
    sed -i '' "/^APP_NAME =/a \
APP_VERSION = ${NEW_VERSION}" Makefile
fi
echo "✓ Updated Makefile"

# Update all .tfvars files in deploy/env/
for tfvars in deploy/env/*.tfvars; do
    if [ -f "$tfvars" ]; then
        if grep -q "^ecr_version =" "$tfvars"; then
            sed -i '' "s/^ecr_version = .*/ecr_version = \"${NEW_VERSION}\"/" "$tfvars"
        else
            echo "ecr_version = \"${NEW_VERSION}\"" >> "$tfvars"
        fi
        echo "✓ Updated $(basename "$tfvars")"
    fi
done

echo
echo "Version update complete!"
