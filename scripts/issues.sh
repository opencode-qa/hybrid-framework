#!/bin/bash
# Refactored GitHub Issue Creation Script
set -euo pipefail

# === CONFIGURATION ===
ASSIGNEE="${1:-$(gh api user --jq '.login')}"
LABEL_FILTER="${2:-}"
ISSUES_DIR=".github/issues"

# === COLORS & ICONS ===
# Theme colors
GREEN='\033[1;32m'
ORANGE='\033[1;33m' # Using 1;33m for consistent bold orange
RED='\033[1;31m'
WHITE='\033[1;37m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'
BOLD='\033[1m'

# Icons without embedded color codes; colors are applied by log functions or printf
ICON_PASS="✓"
ICON_FAIL="✗"
ICON_WARN="💡"
ICON_INFO="ℹ"
ICON_SKIP="➤"

# Custom icons for this script (also without embedded color codes)
ICON_SUCCESS="${ICON_PASS}" # Reusing ICON_PASS
ICON_ON_TRACK="⚪"
ICON_OVERDUE="✗" # Reusing ICON_FAIL
ICON_PROCESSING="🟡"
ICON_NEXT_UPCOMING="🟠"

# Bigger icons for summary (also without embedded color codes)
GREEN_CIRCLE="🟢"
WHITE_CIRCLE="⚪"
RED_CIRCLE="🔴"
WARNING_ICON="⚠️"


# === FUNCTIONS ===

# Function to get display width of a string (handles multi-byte chars/emojis)
get_display_width() {
    echo -n "$1" | wc -m
}

# Log functions now apply color and reset at the end of the line
log_info()    { printf "%b%s %s%b\n" "${BLUE}" "${ICON_INFO}" "$1" "${NC}"; }
log_warn()    { printf "%b%s %s%b\n" "${ORANGE}" "${ICON_WARN}" "$1" "${NC}"; }
log_success() { printf "%b%s %s%b\n" "${GREEN}" "${ICON_SUCCESS}" "$1" "${NC}"; }
log_error()   { printf "%b%s %s%b\n" "${RED}" "${ICON_FAIL}" "$1" "${NC}"; exit 1; }
log_skip()    { printf "%b%s %s%b\n" "${WHITE}" "${ICON_SKIP}" "$1" "${NC}"; }

# Function to print a status line with a colored icon and message
print_status_line() {
    local title=$1 icon_char=$2 status_text=$3
    local color_code # Determine color based on icon_char for this specific function

    case "$icon_char" in
        "${ICON_ON_TRACK}") color_code="${WHITE}" ;;
        "${ICON_SUCCESS}") color_code="${GREEN}" ;;
        "${ICON_FAIL}") color_code="${RED}" ;;
        *) color_code="${WHITE}" ;; # Default color
    esac

    # Calculate max title length for alignment across all calls to this function
    # This assumes print_status_line is called in a loop where max_title_len can be determined
    # For simplicity here, we'll calculate it on the fly, but for perfect column alignment
    # across *all* print_status_line calls, a two-pass approach (like in print_aligned_results)
    # would be needed. For this script, the current usage is mostly sequential, so this works.
    local max_title_len=0
    # A simplified approach for this script's context:
    # Find the max length of the titles that will be printed by this function
    # This would ideally be done globally or passed in. For now, we'll assume a reasonable fixed width
    # or rely on the natural flow if titles are similar in length.
    # To make it robust, we need to gather all titles first, then print.
    # Since this function is called inside a loop for issue creation,
    # we'll make it align based on the longest title encountered so far, or a fixed reasonable length.
    # Let's assume a reasonable max for now, or you'd collect all titles first.
    # For now, let's use a fixed width that accommodates common titles, or you can make it dynamic
    # by collecting all titles and finding the max length before printing.
    # Given the context of the issues.sh, a fixed width is simpler and likely sufficient
    # if titles are generally similar in length.
    local fixed_title_width=40 # Adjust this based on expected max title length

    local current_title_display_len=$(get_display_width "$title")
    local padding_needed=$((fixed_title_width - current_title_display_len))
    local padded_title="${title}"
    for ((i=0; i<padding_needed; i++)); do padded_title+=" "; done

    # Format: "  <icon> → <padded_title> ⇒ <status_text>"
    printf "%b  %s %s %s %s %s%b\n" \
        "${color_code}" \
        "${icon_char}" \
        "→" \
        "${padded_title}" \
        "⇒" \
        "${status_text}" \
        "${NC}"
}


normalize_title() {
    echo "$1" | perl -CSDA -pe 's/\p{So}//g' | sed 's/[^[:alnum:]]//g' | tr '[:upper:]' '[:lower:]'
}

declare -A known_labels=()
declare -a existing_labels_lower=()

cache_existing_labels() {
    mapfile -t existing_labels_lower < <(gh label list --limit 1000 | awk '{print tolower($1)}')
}

create_label_if_needed() {
    local label_name="$1"
    label_name=$(echo "$label_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '"')

    if [[ -n "${known_labels[$label_name]:-}" ]]; then return 0; fi

    local lower_label=$(echo "$label_name" | tr '[:upper:]' '[:lower:]')
    if printf "%s\n" "${existing_labels_lower[@]}" | grep -qx "$lower_label"; then
        known_labels[$label_name]=1
        return 0
    fi

    if gh label create "$label_name" --color "$(echo "$label_name" | sha256sum | head -c 6)" &>/dev/null; then
        known_labels[$label_name]=1
        existing_labels_lower+=("$lower_label")
        return 0
    fi

    return 1
}

create_issue_from_file() {
    local file="$1"
    local raw_title=$(awk -F': ' '/^title:/ {print $2; exit}' "$file")
    local clean_title=$(echo "$raw_title" | sed 's/^"//;s/"$//' | xargs)
    local compare_title=$(normalize_title "$clean_title")

    local existing_titles
    mapfile -t existing_titles < <(gh issue list --limit 1000 --json title --jq '.[].title')

    for title in "${existing_titles[@]}"; do
        if [[ "$(normalize_title "$title")" == "$compare_title" ]]; then
            print_status_line "$clean_title" "$ICON_ON_TRACK" "Already exists"
            return 1 # Return 1 for skipped, as per original logic flow
        fi
    done

    local labels=$(awk -F': ' '/^labels:/ {print $2; exit}' "$file" | tr -d '[]"' | tr ',' '\n' | xargs -n1)

    # Check label filter match
    if [[ -n "$LABEL_FILTER" ]]; then
        local found_match=0
        for label in $labels; do
            if [[ "${label,,}" == "${LABEL_FILTER,,}" ]]; then
                found_match=1
                break
            fi
        done
        if [[ $found_match -eq 0 ]]; then
            print_status_line "$clean_title" "${ICON_SKIP}" "Filtered out by label" # Explicitly log skipped by filter
            return 1 # Return 1 for skipped
        fi
    fi

    local milestone=$(awk -F': ' '/^milestone:/ {print $2; exit}' "$file" | tr -d '"')
    local milestone_arg=()
    if [[ -n "$milestone" ]]; then
        milestone_arg=("--milestone" "$milestone")
    fi

    local body=$(awk '/^---$/ {count++; next} count >= 2 {print}' "$file")

    local label_args=()
    for label in $labels; do
        if create_label_if_needed "$label"; then
            label_args+=("-l" "$label")
        fi
    done

    if issue_url=$(gh issue create -t "$clean_title" -b "$body" --assignee "$ASSIGNEE" "${label_args[@]}" "${milestone_arg[@]}" 2>/dev/null); then
        print_status_line "$clean_title" "$ICON_SUCCESS" "Created"
        return 0
    else
        print_status_line "$clean_title" "$ICON_OVERDUE" "Failed" # Using ICON_OVERDUE for failed
        return 2
    fi
}

main() {
    if [[ ! -d "$ISSUES_DIR" ]]; then
        echo -e "${RED}❌ Directory '$ISSUES_DIR' not found.${NC}"
        exit 1
    fi

    cache_existing_labels

    echo -e "\n${CYAN}🚀 Starting issue creation from '$ISSUES_DIR'...${NC}"
    local created=0 skipped=0 failed=0 total=0
    local current_count=0

    local file_list=("$ISSUES_DIR"/*.md)
    for file in "${file_list[@]}"; do
        [[ -f "$file" ]] || continue
        total=$((total + 1))
    done

    for file in "${file_list[@]}"; do
        [[ -f "$file" ]] || continue
        current_count=$((current_count + 1))
        if create_issue_from_file "$file"; then
            created=$((created + 1))
        else
            status=$?
            if [[ $status -eq 1 ]]; then
                skipped=$((skipped + 1))
            else
                failed=$((failed + 1))
            fi
        fi
    done

    echo -e "\n${BOLD}${PURPLE}📊 Issue Creation Summary:${NC}"

    local max_summary_label_len=0
    # Determine max width for the label column (e.g., "✓ Created")
    local summary_labels_to_measure=("${ICON_PASS} Created" "${ICON_SKIP} Skipped" "${ICON_FAIL} Failed")
    for label_str in "${summary_labels_to_measure[@]}"; do
        local current_len=$(get_display_width "$label_str")
        if (( current_len > max_summary_label_len )); then
            max_summary_label_len="$current_len"
        fi
    done

    # Add some buffer for aesthetics (e.g., 2 spaces for gap)
    max_summary_label_len=$((max_summary_label_len + 2))

    # Print summary with calculated alignment
    local padded_label_part

    # Created line
    local label_text="${ICON_PASS} Created"
    local current_label_display_len=$(get_display_width "$label_text")
    local padding_needed=$((max_summary_label_len - current_label_display_len))
    padded_label_part="${label_text}"
    for ((i=0; i<padding_needed; i++)); do padded_label_part+=" "; done
    printf "%b  %s%3d%b\n" "${GREEN}${BOLD}" "$padded_label_part" "$created" "${NC}"

    # Skipped line
    label_text="${ICON_SKIP} Skipped"
    current_label_display_len=$(get_display_width "$label_text")
    padding_needed=$((max_summary_label_len - current_label_display_len))
    padded_label_part="${label_text}"
    for ((i=0; i<padding_needed; i++)); do padded_label_part+=" "; done
    printf "%b  %s%3d%b\n" "${WHITE}${BOLD}" "$padded_label_part" "$skipped" "${NC}"

    # Failed line
    label_text="${ICON_FAIL} Failed"
    current_label_display_len=$(get_display_width "$label_text")
    padding_needed=$((max_summary_label_len - current_label_display_len))
    padded_label_part="${label_text}"
    for ((i=0; i<padding_needed; i++)); do padded_label_part+=" "; done
    printf "%b  %s%3d%b\n" "${RED}${BOLD}" "$padded_label_part" "$failed" "${NC}"
}

main "$@"
