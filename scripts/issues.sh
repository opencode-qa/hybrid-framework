#!/usr/bin/env bash
set -Eeuo pipefail

# ------------------------------------------------------------------------------
# issues.sh – Batch create GitHub issues from Markdown templates
#
# Enhanced Edition v3.0
#   - Full theming & icons (like milestones.sh)
#   - Creates missing labels automatically
#   - Properly detects open/closed issues (no duplicate creation)
#   - Progress bar, summary, and signature
#   - Dry-run support
#   - Cross‑platform (Linux, macOS, Windows Git Bash / WSL)
# ------------------------------------------------------------------------------

# --- Version check for inherit_errexit (bash 4.4+) ---
if [[ ${BASH_VERSINFO[0]} -gt 4 ]] || [[ ${BASH_VERSINFO[0]} -eq 4 && ${BASH_VERSINFO[1]} -ge 4 ]]; then
    shopt -s inherit_errexit
fi
shopt -s nullglob

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
readonly DEFAULT_ISSUES_DIR=".github/issues"
readonly LABEL_COLOR="0e8a16"   # green (default for new labels)

# ------------------------------------------------------------------------------
# Terminal colors & styles (cross‑platform)
# ------------------------------------------------------------------------------
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]] && [[ "$TERM" != "dumb" ]]; then
    BOLD=$(tput bold 2>/dev/null || echo "")
    GREEN=$(tput setaf 2 2>/dev/null || echo "")
    ORANGE=$(tput setaf 208 2>/dev/null || echo "")
    RED=$(tput setaf 1 2>/dev/null || echo "")
    WHITE=$(tput setaf 7 2>/dev/null || echo "")
    BLUE=$(tput setaf 4 2>/dev/null || echo "")
    PURPLE=$(tput setaf 5 2>/dev/null || echo "")
    CYAN=$(tput setaf 6 2>/dev/null || echo "")
    NC=$(tput sgr0 2>/dev/null || echo "")
else
    BOLD=""
    GREEN=""
    ORANGE=""
    RED=""
    WHITE=""
    BLUE=""
    PURPLE=""
    CYAN=""
    NC=""
fi

# --- Icons & symbols ---
readonly ICON_PASS="${GREEN}✓${NC}"
readonly ICON_WARN="${ORANGE}⚠${NC}"
readonly ICON_FAIL="${RED}✗${NC}"
readonly ICON_INFO="${BLUE}ℹ${NC}"
readonly ICON_SKIP="${WHITE}○${NC}"
readonly ICON_CREATE="${GREEN}✨${NC}"
readonly ICON_LABEL="${CYAN}🏷️${NC}"

# --- Block characters for progress bar ---
readonly BLOCK_PASS="🟩"
readonly BLOCK_WARN="🟧"
readonly BLOCK_FAIL="🟥"
readonly BLOCK_INFO="🟦"
readonly BLOCK_SKIP="⬛"

# ------------------------------------------------------------------------------
# Global state
# ------------------------------------------------------------------------------
declare -A COUNTS=(
    ["pass"]=0
    ["warn"]=0
    ["fail"]=0
    ["info"]=0
    ["skip"]=0
)
declare -a CHECK_RESULTS=()          # for progress bar (P/W/F/I/S)
declare -A EXISTING_ISSUES           # key = normalized title → "STATE|NUMBER|TITLE"
declare -A EXISTING_LABELS           # label name → 1

# ------------------------------------------------------------------------------
# Logging functions
# ------------------------------------------------------------------------------
log_info() {
    echo -e "${ICON_INFO} ${BLUE}${BOLD}$*${NC}" >&2
    COUNTS["info"]=$((COUNTS["info"] + 1))
    CHECK_RESULTS+=("info")
}

log_warn() {
    echo -e "${ICON_WARN} ${ORANGE}${BOLD}$*${NC}" >&2
    COUNTS["warn"]=$((COUNTS["warn"] + 1))
    CHECK_RESULTS+=("warn")
}

log_success() {
    echo -e "${ICON_PASS} ${GREEN}${BOLD}$*${NC}" >&2
    COUNTS["pass"]=$((COUNTS["pass"] + 1))
    CHECK_RESULTS+=("pass")
}

log_error() {
    echo -e "${ICON_FAIL} ${RED}${BOLD}$*${NC}" >&2
    COUNTS["fail"]=$((COUNTS["fail"] + 1))
    CHECK_RESULTS+=("fail")
}

log_skip() {
    echo -e "${ICON_SKIP} ${WHITE}${BOLD}$*${NC}" >&2
    COUNTS["skip"]=$((COUNTS["skip"] + 1))
    CHECK_RESULTS+=("skip")
}

log_duplicate() {
    local state="$1"
    local number="$2"
    local title="$3"
    local message="Issue already exists (${state}): #${number} - ${title}"
    if [[ "$state" == "OPEN" ]]; then
        echo -e "${ICON_SKIP} ${WHITE}${BOLD}${message}${NC}" >&2
    else
        echo -e "${ICON_SKIP} ${RED}${BOLD}${message}${NC}" >&2
    fi
    COUNTS["skip"]=$((COUNTS["skip"] + 1))
    CHECK_RESULTS+=("skip")
}

fatal() {
    echo -e "\n${ICON_FAIL} ${RED}${BOLD}FATAL ERROR: $1${NC}" >&2
    exit 1
}

# ------------------------------------------------------------------------------
# Cross‑platform temp file creation
# ------------------------------------------------------------------------------
create_temp_file() {
    local prefix="${1:-issues-temp}"
    if command -v mktemp >/dev/null 2>&1; then
        local tmp_file
        if tmp_file=$(mktemp 2>/dev/null); then
            echo "$tmp_file"
            return 0
        fi
    fi
    # Fallbacks
    local fallback_file
    if [[ -d /tmp ]]; then
        fallback_file="/tmp/${prefix}-$$-${RANDOM}"
    elif [[ -d "$TMPDIR" ]]; then
        fallback_file="${TMPDIR}/${prefix}-$$-${RANDOM}"
    elif [[ -d "$TEMP" ]]; then
        fallback_file="${TEMP}/${prefix}-$$-${RANDOM}"
    else
        fallback_file="./${prefix}-$$-${RANDOM}"
    fi
    touch "$fallback_file"
    echo "$fallback_file"
}

TEMP_FILES=()
cleanup() {
    for file in "${TEMP_FILES[@]:-}"; do
        [[ -f "$file" ]] && rm -f "$file" 2>/dev/null || true
    done
}
trap cleanup EXIT

# ------------------------------------------------------------------------------
# Tool validation
# ------------------------------------------------------------------------------
validate_required_tools() {
    local required_tools=("gh" "jq" "git")
    local missing=()
    for tool in "${required_tools[@]}"; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        fatal "Missing required tools: ${missing[*]}\nInstall with:\n  macOS: brew install ${missing[*]}\n  Linux: sudo apt install ${missing[*]}\n  Windows (choco): choco install ${missing[*]}"
    fi
    log_success "All required tools are available"
}

# ------------------------------------------------------------------------------
# Title normalisation (without perl)
# ------------------------------------------------------------------------------
normalize_title() {
    local input="$1"
    local result=""
    if command -v perl >/dev/null 2>&1; then
        result=$(echo "$input" | perl -CSDA -pe 's/\p{So}//g' 2>/dev/null | sed 's/[^[:alnum:]]//g' | tr '[:upper:]' '[:lower:]')
    else
        # Remove common emojis and non‑alnum characters
        result=$(echo "$input" | sed 's/[🟢🔴🔵🟠🟣🟡🟩🟪⬛⬜🟧🟦🟥✅❌⚠️ℹ️○✓✗🚀🔖🎯📝📊]//g' | sed 's/[^a-zA-Z0-9]//g' | tr '[:upper:]' '[:lower:]')
    fi
    if [[ -z "$result" ]]; then
        # Fallback: hash of the input
        result=$(echo "$input" | sha256sum | cut -c1-16 2>/dev/null || echo "$input" | sum | cut -c1-16)
    fi
    echo "$result"
}

# ------------------------------------------------------------------------------
# Cache existing issues (open + closed)
# ------------------------------------------------------------------------------
cache_existing_issues() {
    log_info "Fetching existing issues from GitHub (all states) ..."
    local all_issues
    if ! all_issues=$(gh issue list --state all --limit 1000 --json title,number,state 2>/dev/null); then
        fatal "Failed to fetch issues. Check GitHub authentication."
    fi
    if [[ -z "$all_issues" ]] || [[ "$all_issues" == "[]" ]]; then
        log_warn "No existing issues found."
        return 0
    fi
    EXISTING_ISSUES=()
    local count=0
    while IFS= read -r issue; do
        [[ -z "$issue" ]] && continue
        local title number state normalized
        title=$(echo "$issue" | jq -r '.title' 2>/dev/null || echo "")
        number=$(echo "$issue" | jq -r '.number' 2>/dev/null || echo "")
        state=$(echo "$issue" | jq -r '.state' 2>/dev/null | tr '[:lower:]' '[:upper:]')
        if [[ -n "$title" ]]; then
            normalized=$(normalize_title "$title")
            EXISTING_ISSUES["$normalized"]="${state}|${number}|${title}"
            count=$((count + 1))
        fi
    done < <(echo "$all_issues" | jq -c '.[]' 2>/dev/null || echo "")
    log_success "Cached $count existing issue(s) (open + closed)"
}

# ------------------------------------------------------------------------------
# Cache existing labels
# ------------------------------------------------------------------------------
cache_existing_labels() {
    log_info "Fetching existing labels from repository ..."
    local labels_json
    if ! labels_json=$(gh label list --limit 100 --json name 2>/dev/null); then
        log_warn "Unable to fetch labels. Label creation may fail if labels are missing."
        return 0
    fi
    EXISTING_LABELS=()
    local count=0
    while IFS= read -r label; do
        [[ -z "$label" ]] && continue
        local name
        name=$(echo "$label" | jq -r '.name' 2>/dev/null || echo "")
        if [[ -n "$name" ]]; then
            EXISTING_LABELS["$name"]=1
            count=$((count + 1))
        fi
    done < <(echo "$labels_json" | jq -c '.[]' 2>/dev/null || echo "")
    log_success "Cached $count existing label(s)"
}

# ------------------------------------------------------------------------------
# Ensure label exists (create if missing)
# ------------------------------------------------------------------------------
ensure_label() {
    local label="$1"
    if [[ -n "${EXISTING_LABELS[$label]:-}" ]]; then
        return 0
    fi
    log_info "Creating missing label: ${label}"
    if ! gh label create "$label" --color "$LABEL_COLOR" --description "Auto‑created by issues.sh" >/dev/null 2>&1; then
        log_warn "Failed to create label '$label' (permissions?)"
        return 1
    fi
    EXISTING_LABELS["$label"]=1
    log_success "Label created: ${label}"
    return 0
}

# ------------------------------------------------------------------------------
# Check if an issue already exists (by normalized title)
# ------------------------------------------------------------------------------
issue_exists() {
    local normalized="$1"
    [[ -n "${EXISTING_ISSUES[$normalized]:-}" ]]
}

# ------------------------------------------------------------------------------
# Parse YAML frontmatter (supports arrays and comma‑separated values)
# ------------------------------------------------------------------------------
parse_yaml_list() {
    local yaml_content="$1"
    local field_name="$2"
    local -a result=()
    if command -v yq >/dev/null 2>&1; then
        # Try as YAML array first
        local array_items
        array_items=$(echo "$yaml_content" | yq eval ".${field_name}[]" - 2>/dev/null || true)
        if [[ -n "$array_items" ]]; then
            while IFS= read -r item; do
                [[ -n "$item" ]] && result+=("$item")
            done <<< "$array_items"
        else
            # Fallback: single string (possibly comma‑separated)
            local single_value
            single_value=$(echo "$yaml_content" | yq eval ".${field_name}" - 2>/dev/null | sed 's/^"//;s/"$//' || true)
            if [[ -n "$single_value" && "$single_value" != "null" ]]; then
                IFS=',' read -ra parts <<< "$single_value"
                for p in "${parts[@]}"; do
                    p=$(echo "$p" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                    [[ -n "$p" ]] && result+=("$p")
                done
            fi
        fi
    else
        # Fallback using grep/sed
        local line_value
        line_value=$(echo "$yaml_content" | grep -m1 "^${field_name}:" | sed "s/^${field_name}:[[:space:]]*//" | sed 's/^"//;s/"$//' | sed 's/^\[//;s/\]$//')
        if [[ -n "$line_value" ]]; then
            IFS=',' read -ra parts <<< "$line_value"
            for p in "${parts[@]}"; do
                p=$(echo "$p" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^- //')
                [[ -n "$p" ]] && result+=("$p")
            done
        fi
    fi
    for item in "${result[@]}"; do
        echo "$item"
    done
}

parse_issue_metadata() {
    local file="$1"
    ISSUE_TITLE=""
    ISSUE_MILESTONE=""
    ISSUE_LABELS_ARRAY=()
    ISSUE_ASSIGNEES_ARRAY=()
    # Extract frontmatter (between --- and ---)
    local frontmatter
    frontmatter=$(
        awk '
            /^---$/ {
                count++
                if (count == 1) next
                if (count == 2) exit
            }
            count == 1
        ' "$file" | sed 's/\r$//'
    )
    if [[ -z "$frontmatter" ]]; then
        log_error "No YAML frontmatter found in $file"
        return 1
    fi
    # Title
    if command -v yq >/dev/null 2>&1; then
        ISSUE_TITLE=$(echo "$frontmatter" | yq eval '.title // ""' - 2>/dev/null | sed 's/^"//;s/"$//')
        ISSUE_MILESTONE=$(echo "$frontmatter" | yq eval '.milestone // ""' - 2>/dev/null | sed 's/^"//;s/"$//')
    else
        ISSUE_TITLE=$(echo "$frontmatter" | grep -m1 '^title:' | sed 's/^title:[[:space:]]*//;s/^"//;s/"$//')
        ISSUE_MILESTONE=$(echo "$frontmatter" | grep -m1 '^milestone:' | sed 's/^milestone:[[:space:]]*//;s/^"//;s/"$//')
    fi
    # Labels
    while IFS= read -r label; do
        [[ -n "$label" ]] && ISSUE_LABELS_ARRAY+=("$label")
    done < <(parse_yaml_list "$frontmatter" "labels")
    # Assignees
    while IFS= read -r assignee; do
        [[ -n "$assignee" ]] && ISSUE_ASSIGNEES_ARRAY+=("$assignee")
    done < <(parse_yaml_list "$frontmatter" "assignees")
    # Trim
    ISSUE_TITLE=$(echo "$ISSUE_TITLE" | xargs)
    ISSUE_MILESTONE=$(echo "$ISSUE_MILESTONE" | xargs)
    if [[ -z "$ISSUE_TITLE" ]]; then
        log_error "Missing issue title in $file"
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# Create a single issue
# ------------------------------------------------------------------------------
create_issue_from_file() {
    local file="$1"
    local assignee_override="$2"
    local dry_run="${3:-false}"

    if ! parse_issue_metadata "$file"; then
        return 2
    fi

    local normalized_title
    normalized_title=$(normalize_title "$ISSUE_TITLE")
    if issue_exists "$normalized_title"; then
        IFS='|' read -r existing_state existing_number existing_title <<< "${EXISTING_ISSUES[$normalized_title]}"
        log_duplicate "$existing_state" "$existing_number" "$ISSUE_TITLE"
        return 1
    fi

    # Ensure all required labels exist in the repository
    for label in "${ISSUE_LABELS_ARRAY[@]}"; do
        ensure_label "$label" || log_warn "Could not ensure label: $label"
    done

    # Extract issue body (everything after second ---)
    local body
    body=$(
        awk '
            /^---$/ {
                count++
                next
            }
            count >= 2
        ' "$file" | sed 's/\r$//'
    )
    local tmp_body
    tmp_body=$(create_temp_file "issue-body")
    TEMP_FILES+=("$tmp_body")
    printf "%s\n" "$body" > "$tmp_body"

    # Build gh issue create command
    local cmd=(gh issue create --title "$ISSUE_TITLE" --body-file "$tmp_body")
    for label in "${ISSUE_LABELS_ARRAY[@]}"; do
        cmd+=(--label "$label")
    done
    # Determine assignee (first from frontmatter, else override, else none)
    local final_assignee=""
    if [[ ${#ISSUE_ASSIGNEES_ARRAY[@]} -gt 0 ]]; then
        final_assignee="${ISSUE_ASSIGNEES_ARRAY[0]}"
    elif [[ -n "$assignee_override" ]]; then
        final_assignee="$assignee_override"
    fi
    [[ -n "$final_assignee" ]] && cmd+=(--assignee "$final_assignee")
    [[ -n "$ISSUE_MILESTONE" ]] && cmd+=(--milestone "$ISSUE_MILESTONE")

    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Would create issue: $ISSUE_TITLE"
        return 0
    fi

    local issue_output
    if issue_output=$("${cmd[@]}" 2>&1); then
        log_success "Created issue: $ISSUE_TITLE → $issue_output"
        # Update cache so we don't recreate in the same run
        EXISTING_ISSUES["$normalized_title"]="OPEN|NEW|$ISSUE_TITLE"
        return 0
    else
        log_error "Failed to create issue: $ISSUE_TITLE"
        echo "$issue_output" >&2
        return 2
    fi
}

# ------------------------------------------------------------------------------
# Progress bar (coloured blocks)
# ------------------------------------------------------------------------------
print_progress_bar() {
    local total=${#CHECK_RESULTS[@]}
    [[ $total -eq 0 ]] && return
    local bar=""
    for r in "${CHECK_RESULTS[@]}"; do
        case "$r" in
            "pass") bar+="$BLOCK_PASS" ;;
            "warn") bar+="$BLOCK_WARN" ;;
            "fail") bar+="$BLOCK_FAIL" ;;
            "info") bar+="$BLOCK_INFO" ;;
            "skip") bar+="$BLOCK_SKIP" ;;
        esac
    done
    echo -e "\n${WHITE}Progress: [${bar}] 100% (${total}/${total} checks)${NC}"
}

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
print_summary() {
    echo -e "\n${CYAN}${BOLD}📊 Summary:${NC}"
    printf "  %b  ${GREEN}${BOLD}Created${NC}   ${GREEN}🟢 ⇒ ${GREEN}${BOLD}%d${NC}\n" \
        "${ICON_PASS}" "${COUNTS[pass]}"
    printf "  %b  ${WHITE}${BOLD}Skipped${NC}   ${WHITE}⚫ ⇒ ${WHITE}${BOLD}%d${NC}\n" \
        "${ICON_SKIP}" "${COUNTS[skip]}"
    printf "  %b  ${RED}${BOLD}Failed${NC}    ${RED}🔴 ⇒ ${RED}${BOLD}%d${NC}\n" \
        "${ICON_FAIL}" "${COUNTS[fail]}"
    printf "  %b  ${BLUE}${BOLD}Info${NC}      ${BLUE}🔵 ⇒ ${BLUE}${BOLD}%d${NC}\n" \
        "${ICON_INFO}" "${COUNTS[info]}"
    printf "  %b  ${ORANGE}${BOLD}Warnings${NC} ${ORANGE}🟠 ⇒ ${ORANGE}${BOLD}%d${NC}\n" \
        "${ICON_WARN}" "${COUNTS[warn]}"
}

# ------------------------------------------------------------------------------
# Author signature (matching milestones.sh style)
# ------------------------------------------------------------------------------
print_signature() {
    echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}                          Author Details                                  ${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}ANUJ KUMAR${NC}"
    echo -e "${CYAN}🏅 QA Lead & AI-Assisted Testing Specialist${NC}"
    echo -e "${ORANGE}📧 Email: ${BLUE}anujpatiyal@live.in${NC}"
    echo -e "${ORANGE}🔗 LinkedIn: ${BLUE}https://www.linkedin.com/in/anuj-kumar-qa/${NC}"
    echo -e "\n${WHITE}Completed at: $(date +"%d-%b-%Y %H:%M:%S")${NC}\n"
}

# ------------------------------------------------------------------------------
# Banner
# ------------------------------------------------------------------------------
print_banner() {
    echo -e "\n${PURPLE}╔══════════════════════════════════════════════════════════════╗"
    echo -e "║${NC}${PURPLE}          📝  G I T H U B   I S S U E   C R E A T O R        ${NC}${PURPLE}║"
    echo -e "╚══════════════════════════════════════════════════════════════╝${NC}"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
    local start_time
    start_time=$(date +%s)
    print_banner

    local assignee=""
    local label_filter=""
    local issues_dir="$DEFAULT_ISSUES_DIR"
    local dry_run=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --assignee)
                assignee="$2"
                shift 2
                ;;
            --label-filter)
                label_filter="$2"
                shift 2
                ;;
            --issues-dir)
                issues_dir="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --assignee USER       Assign created issues to this GitHub user
  --label-filter LABEL  Only process issues containing this label
  --issues-dir DIR      Directory containing issue templates (default: .github/issues)
  --dry-run             Simulate issue creation without GitHub API
  -h, --help           Show this help

Examples:
  $0                                    # Create all issues
  $0 --dry-run                         # Preview only
  $0 --assignee opencode-qa            # Assign to specific user
  $0 --label-filter enhancement        # Filter by label
EOF
                exit 0
                ;;
            *)
                fatal "Unknown option: $1"
                ;;
        esac
    done

    # Validate environment
    validate_required_tools
    if [[ "$dry_run" == "false" ]]; then
        if ! gh auth status >/dev/null 2>&1; then
            fatal "GitHub CLI not authenticated. Run: gh auth login"
        fi
        # Default assignee = current GitHub user if not provided
        if [[ -z "$assignee" ]]; then
            assignee=$(gh api user --jq '.login' 2>/dev/null || echo "")
            [[ -z "$assignee" ]] && fatal "Unable to determine GitHub user. Specify --assignee"
        fi
    fi

    # Validate issues directory
    if [[ ! -d "$issues_dir" ]]; then
        fatal "Directory not found: $issues_dir"
    fi

    # Cache existing data (only when not dry‑run)
    if [[ "$dry_run" == "false" ]]; then
        cache_existing_issues
        cache_existing_labels
    else
        log_info "DRY RUN: Skipping cache of existing issues/labels"
    fi

    # Gather markdown files
    shopt -s nullglob
    local files=("$issues_dir"/*.md)
    shopt -u nullglob
    if [[ ${#files[@]} -eq 0 ]]; then
        fatal "No markdown issue files found in $issues_dir"
    fi

    log_info "Processing ${#files[@]} issue template(s) from $issues_dir"
    [[ -n "$assignee" ]] && log_info "Default assignee: $assignee"
    [[ -n "$label_filter" ]] && log_info "Label filter: $label_filter"

    local created=0 skipped=0 failed=0

    for file in "${files[@]}"; do
        [[ -f "$file" ]] || continue

        # Apply label filter if requested
        if [[ -n "$label_filter" ]]; then
            # Quick parse just to get labels
            parse_issue_metadata "$file" >/dev/null 2>&1
            local found=false
            for lbl in "${ISSUE_LABELS_ARRAY[@]}"; do
                if [[ "${lbl,,}" == "${label_filter,,}" ]]; then
                    found=true
                    break
                fi
            done
            if [[ "$found" == "false" ]]; then
                log_skip "Skipping $(basename "$file") (label mismatch)"
                skipped=$((skipped + 1))
                continue
            fi
        fi

        set +e
        create_issue_from_file "$file" "$assignee" "$dry_run"
        local exit_code=$?
        set -e
        case $exit_code in
            0) created=$((created + 1)) ;;
            1) skipped=$((skipped + 1)) ;;
            2) failed=$((failed + 1)) ;;
        esac
    done

    # Update counts for final summary
    COUNTS["pass"]=$created
    COUNTS["skip"]=$skipped
    COUNTS["fail"]=$failed

    print_progress_bar
    print_summary
    print_signature

    local end_time
    end_time=$(date +%s)
    echo -e "\n${WHITE}⏱ Completed in $((end_time - start_time)) seconds${NC}"

    if [[ $failed -gt 0 ]]; then
        echo -e "\n${RED}❌ Issue creation completed with ${failed} failure(s).${NC}"
        exit 1
    fi
    echo -e "\n${GREEN}🎉 Successfully processed ${created} new issue(s).${NC}"
}

main "$@"