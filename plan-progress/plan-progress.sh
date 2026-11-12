#!/bin/bash

# Optional directory argument
if [ -n "$1" ]; then
    if [ -d "$1" ]; then
        cd "$1" || exit 1
    else
        echo "Directory not found: $1"
        exit 1
    fi
fi

# Find plan.md file
current_dir="$(pwd)"
home_dir="$HOME"
plan_file=""
dir="$current_dir"
while [ "$dir" != "/" ] && [ "$dir" != "$home_dir" ]; do
    if [ -f "$dir/plan.md" ]; then
        plan_file="$dir/plan.md"
        break
    fi
    dir="$(dirname "$dir")"
done
# If not found, check current dir and home dir
if [ -z "$plan_file" ]; then
    if [ -f "$current_dir/plan.md" ]; then
        plan_file="$current_dir/plan.md"
    elif [ -f "$home_dir/plan.md" ]; then
        plan_file="$home_dir/plan.md"
    fi
fi

if [ -z "$plan_file" ]; then
    echo "No plan.md file found in current directory or parent directories."
    exit 0
fi

echo "Found plan.md at: $plan_file"
echo ""

# Count checkboxes (support -, *, + as list markers)
total=$(grep -c "^[[:space:]]*[-*+][[:space:]]*\[[ x]\]" "$plan_file" || echo "0")
completed=$(grep -c "^[[:space:]]*[-*+][[:space:]]*\[x\]" "$plan_file" || echo "0")
if [ "$total" -eq 0 ]; then
    echo "No checkboxes found in plan.md."
    exit 0
fi
incomplete=$((total - completed))
percentage=$((completed * 100 / total))

# Progress bar
bar_length=20
filled=$((completed * bar_length / total))
empty=$((bar_length - filled))
bar=""
for ((i=0; i<filled; i++)); do bar="${bar}█"; done
for ((i=0; i<empty; i++)); do bar="${bar}░"; done

echo "Progress: $completed/$total checkboxes completed ($percentage%)"
echo "[$bar]"
echo ""

# List incomplete tasks (optional)
if [ "$incomplete" -gt 0 ]; then
    echo "Remaining tasks:"
    grep -n "^[[:space:]]*[-*+][[:space:]]*\[ \]" "$plan_file" | head -10 | while read line; do
        echo "  $line"
    done
    if [ "$incomplete" -gt 10 ]; then
        echo "  ... and $((incomplete - 10)) more."
    fi
fi