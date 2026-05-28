#!/usr/bin/env bash
set -eo pipefail

# === Configuration Constants ===
readonly TARGET_BRANCH="dev"
readonly METADATA_DIR=".github/features"
readonly MAX_CI_RETRIES=20
readonly CI_RETRY_DELAY=15  # seconds
readonly LABEL_COLOR="0366d6"
readonly REQUIRED_FIELDS=("title" "labels")
readonly CI_CHECK_ENABLED=true

# === ANSI Color Codes ===
readonly BOLD='\033[1m'
readonly GREEN='\033[1;32m'
readonly ORANGE='\033[38;5;214m'
readonly RED='\033[1;31m'
readonly WHITE='\033[1;37m'
readonly BLUE='\033[1;34m'
readonly PURPLE='\033[1;35m'
readonly CYAN='\033[1;36m'
readonly NC='\033[0m'

# === Icons ===
readonly ICON_PASS="${GREEN}✓${NC}"
readonly ICON_WARN="${ORANGE}⚠${NC}"
readonly ICON_FAIL="${RED}✗${NC}"
readonly ICON_INFO="${BLUE}ℹ${NC}"
readonly ICON_SKIP="${WHITE}○${NC}"

# === Global State ===
COUNT_PASS=0
COUNT_WARN=0
COUNT_FAIL=0
COUNT_INFO=0
COUNT_SKIP=0
CHECK_RESULTS=()

declare -g PR_URL="" PR_NUMBER=""
declare -g TITLE="" MILESTONE="" LINKED_ISSUE=""
declare -a ASSIGNEES_ARRAY=()
declare -a REVIEWERS_ARRAY=()
declare -a LABELS_ARRAY=()

# === Helper Functions ===

log_info() {
    echo -e "${ICON_INFO} ${BLUE}$1${NC}" >&2
    COUNT_INFO=$((COUNT_INFO + 1))
    CHECK_RESULTS+=("info")
}

log_warn() {
    echo -e "${ICON_WARN} ${ORANGE}$1${NC}" >&2
    COUNT_WARN=$((COUNT_WARN + 1))
    CHECK_RESULTS+=("warn")
}

log_success() {
    echo -e "${ICON_PASS} ${GREEN}$1${NC}" >&2
    COUNT_PASS=$((COUNT_PASS + 1))
    CHECK_RESULTS+=("pass")
}

log_error() {
    echo -e "${ICON_FAIL} ${RED}$1${NC}" >&2
    COUNT_FAIL=$((COUNT_FAIL + 1))
    CHECK_RESULTS+=("fail")
}

fatal_error() {
    echo -e "\n${ICON_FAIL} ${RED}FATAL ERROR: $1${NC}" >&2
    exit 1
}

log_skip() {
    echo -e "${ICON_SKIP} ${WHITE}$1${NC}" >&2
    COUNT_SKIP=$((COUNT_SKIP + 1))
    CHECK_RESULTS+=("skip")
}

validate_required_tools() {
    local required_tools=("gh" "jq" "git" "yq" "awk")
    local missing_tools=()
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        fatal_error "Missing required tools: ${missing_tools[*]}. Please install them."
    fi
}

# ======================================================
# ENHANCED: Supports both YAML arrays AND comma-separated strings
# ======================================================
get_yaml_value() {
    local field=$1
    local file=$2
    awk '/^---$/{if (++n == 1) next; else exit} n' "$file" | yq eval ".${field} | select(. != null)" - 2>/dev/null || echo ""
}

get_yaml_array() {
    local field=$1
    local file=$2
    # Try YAML array first ( - item )
    local result
    result=$(awk '/^---$/{if (++n == 1) next; else exit} n' "$file" | yq eval ".${field}[] | select(. != null)" - 2>/dev/null)
    if [[ -n "$result" ]]; then
        echo "$result"
        return
    fi
    # Fallback: single string (possibly comma separated)
    local single
    single=$(awk '/^---$/{if (++n == 1) next; else exit} n' "$file" | yq eval ".${field} | select(. != null)" - 2>/dev/null)
    if [[ -n "$single" ]]; then
        # Split by comma and trim spaces
        echo "$single" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$'
    fi
}

# === PR Processing Functions ===

get_current_branch() {
    git rev-parse --abbrev-ref HEAD
}

get_repo_name() {
    gh repo view --json nameWithOwner -q '.nameWithOwner'
}

get_pr_data() {
    local branch=$1
    gh pr list --head "$branch" --base "$TARGET_BRANCH" \
        --json number,state,url --limit 1 2>/dev/null || echo "[]"
}

wait_for_ci_completion() {
    if [[ "$CI_CHECK_ENABLED" != "true" ]]; then
        log_skip "CI checks are disabled. Bypassing wait."
        return 0
    fi

    local repo=$1
    local branch=$2
    local attempts=0

    log_info "Checking GitHub Actions status for branch '${branch}'..."

    while [[ $attempts -lt $MAX_CI_RETRIES ]]; do
        local status_data
        status_data=$(gh api "repos/$repo/actions/runs?branch=$branch&per_page=1" -q '.workflow_runs[0] // null' 2>/dev/null || echo "null")

        if [[ "$status_data" == "null" ]]; then
            log_warn "No CI runs found for branch $branch. Moving forward."
            return 0
        fi

        local status
        local conclusion
        status=$(echo "$status_data" | jq -r '.status')
        conclusion=$(echo "$status_data" | jq -r '.conclusion')

        case "$status-$conclusion" in
            "completed-success")
                log_success "Fast CI checks passed successfully!"
                return 0
                ;;
            "completed-failure"|"completed-cancelled"|"completed-timed_out")
                fatal_error "CI checks failed with conclusion: ${conclusion^^}. Fix CI before creating a PR."
                ;;
            *)
                log_info "CI status: ${status:-unknown} (attempt $((attempts+1))/$MAX_CI_RETRIES)... waiting ${CI_RETRY_DELAY}s."
                sleep $CI_RETRY_DELAY
                ;;
        esac

        attempts=$((attempts + 1))
    done

    fatal_error "CI did not complete within the expected time limit."
}

generate_dynamic_metadata() {
    local milestone=$1
    local title=$2
    local current_branch=$3
    local linked_issue=$4
    local pr_num=$5
    local pr_url=$6

    cat <<EOF

## 🔗 Related Milestone
- 📍 Milestone: \`${milestone}\` – ${title}
- 🛠️ Source Branch: **\`${current_branch}\`**
- 🎯 Target Branch: **\`${TARGET_BRANCH}\`**

EOF

    if [[ -n "$linked_issue" ]]; then
        echo "## Related Issues:"
        echo "- Related to #${linked_issue}"
        echo
    fi

    if [[ -n "$pr_num" ]]; then
        echo "## 🔀 Merged PRs"
        echo "- ✅ [#${pr_num}](${pr_url}) – \`${current_branch} → ${TARGET_BRANCH}\`: ${title}"
    fi
}

generate_author_section() {
    cat <<EOF

## 👤 Author
**ANUJ KUMAR** | 🏅 QA Lead & AI-Assisted Testing Specialist
*Specializing in scalable test automation and AI-driven quality assurance.*

📧 Email: [anujpatiyal@live.in](mailto:anujpatiyal@live.in)

🔗 LinkedIn: [https://www.linkedin.com/in/anuj-kumar-qa/](https://www.linkedin.com/in/anuj-kumar-qa/)
EOF
}

process_labels() {
    local pr_num="$1"
    local repo="$2"
    shift 2
    local desired_labels=("$@")

    if [[ ${#desired_labels[@]} -eq 0 ]]; then
        log_skip "No labels specified in metadata"
        return
    fi

    log_info "Processing labels..."
    local current_repo_labels
    current_repo_labels=$(gh api "repos/$repo/labels" --jq '.[].name' 2>/dev/null || echo "")

    local current_pr_labels
    current_pr_labels=$(gh pr view "$pr_num" --json labels --jq '.labels[].name' 2>/dev/null || echo "")

    for label in "${desired_labels[@]}"; do
        if echo "$current_pr_labels" | grep -Fxq "$label"; then
            log_skip "Label '$label' already exists on PR"
            continue
        fi

        if ! echo "$current_repo_labels" | grep -Fxq "$label"; then
            log_info "Creating missing label '$label' in repository"
            gh label create "$label" --color "$LABEL_COLOR" --description "Created via PR script" >/dev/null 2>&1 \
                || log_warn "Failed to create label '$label' (Check permissions)"
        fi

        log_info "Adding label '$label' to PR"
        gh pr edit "$pr_num" --add-label "$label" >/dev/null 2>&1 \
            && log_success "Added label '$label'" \
            || log_error "Failed to add label '$label'"
    done
}

process_milestone() {
    local pr_num=$1
    local desired_milestone=$2

    if [[ -z "$desired_milestone" ]]; then
        log_skip "No milestone specified in metadata"
        return
    fi

    local current_milestone
    current_milestone=$(gh pr view "$pr_num" --json milestone -q '.milestone.title // empty' 2>/dev/null)

    if [[ "$current_milestone" == "$desired_milestone" ]]; then
        log_skip "Milestone '$desired_milestone' already set"
    else
        log_info "Setting milestone '$desired_milestone'"
        gh pr edit "$pr_num" --milestone "$desired_milestone" >/dev/null 2>&1 \
            && log_success "Milestone set to '$desired_milestone'" \
            || log_error "Failed to set milestone '$desired_milestone'"
    fi
}

process_people() {
    local pr_num="$1"
    local flag_name="$2"   # '--add-assignee' or '--add-reviewer'
    local entity_name="$3" # 'Assignee' or 'Reviewer'
    shift 3
    local desired_people=("$@")

    if [[ ${#desired_people[@]} -eq 0 ]]; then
        log_skip "No ${entity_name}s specified in metadata"
        return
    fi

    log_info "Processing ${entity_name}s..."
    local existing_people
    if [[ "$entity_name" == "Assignee" ]]; then
        existing_people=$(gh pr view "$pr_num" --json assignees -q '.assignees[].login' 2>/dev/null || echo "")
    else
        existing_people=$(gh pr view "$pr_num" --json reviewRequests -q '.reviewRequests[].login' 2>/dev/null || echo "")
    fi

    for person in "${desired_people[@]}"; do
        if echo "$existing_people" | grep -Fxq "$person"; then
            log_skip "${entity_name} '$person' already attached"
        else
            log_info "Adding ${entity_name}: '$person'"
            gh pr edit "$pr_num" "$flag_name" "$person" >/dev/null 2>&1 \
                && log_success "Added ${entity_name} '$person'" \
                || log_error "Failed to add ${entity_name} '$person'"
        fi
    done
}

print_progress_bar() {
    local total_checks=${#CHECK_RESULTS[@]}
    local filled_bar=""

    for result in "${CHECK_RESULTS[@]}"; do
        case "$result" in
            "pass") filled_bar+="🟩";;
            "warn") filled_bar+="🟧";;
            "fail") filled_bar+="🟥";;
            "info") filled_bar+="🟦";;
            "skip") filled_bar+="⬛";;
        esac
    done

    echo -e "\nProgress: [${filled_bar}] 100% (${total_checks}/$total_checks ops)"
}

print_summary() {
    echo -e "\n${WHITE}📊 Validation Summary:${NC}"
    printf "  ${ICON_PASS} Passed    ${GREEN}🟢  ⇒ %2d\n" "$COUNT_PASS"
    printf "  ${ICON_WARN} Warnings  ${ORANGE}🟠  ⇒ %2d\n" "$COUNT_WARN"
    printf "  ${ICON_FAIL} Failures  ${RED}🔴  ⇒ %2d\n" "$COUNT_FAIL"
    printf "  ${ICON_INFO} Info      ${BLUE}🔵  ⇒ %2d\n" "$COUNT_INFO"
    printf "  ${ICON_SKIP} Skipped   ${WHITE}⚫  ⇒ %2d\n" "$COUNT_SKIP"
}

print_signature() {
    echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}                          Author Details                                  ${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}ANUJ KUMAR${NC}"
    echo -e "${CYAN}🏅🏅 QA Lead & AI-Assisted Testing Specialist${NC}"
    echo -e "${ORANGE}📧 Email: ${BLUE}anujpatiyal@live.in${NC}"
    echo -e "${ORANGE}🔗 LinkedIn: ${BLUE}https://www.linkedin.com/in/anuj-kumar-qa/${NC}"
    echo -e "\n${WHITE}Completed at: $(date +"%d-%b-%Y %H:%M:%S")${NC}\n"
}

# === Main (with the critical sed fix) ===

main() {
    validate_required_tools

    local start_time=$(date +%s)
    local current_branch=$(get_current_branch)
    local branch_key="${current_branch#feature/}"
    local metadata_file="${METADATA_DIR}/${branch_key}.md"
    local repo=$(get_repo_name)

    log_info "Current branch detected: ${current_branch}"
    log_info "Target branch for PR: ${TARGET_BRANCH}"

    [[ -f "$metadata_file" ]] || fatal_error "Metadata file not found: $metadata_file"
    log_success "Found metadata file: $metadata_file"

    TITLE=$(get_yaml_value "title" "$metadata_file")
    MILESTONE=$(get_yaml_value "milestone" "$metadata_file")
    LINKED_ISSUE=$(get_yaml_value "linked_issue" "$metadata_file")

    # Load arrays (handles both YAML lists and comma-separated strings)
    while IFS= read -r line; do [[ -n "$line" ]] && LABELS_ARRAY+=("$line"); done < <(get_yaml_array "labels" "$metadata_file")
    while IFS= read -r line; do [[ -n "$line" ]] && ASSIGNEES_ARRAY+=("$line"); done < <(get_yaml_array "assignees" "$metadata_file")
    while IFS= read -r line; do [[ -n "$line" ]] && REVIEWERS_ARRAY+=("$line"); done < <(get_yaml_array "reviewers" "$metadata_file")

    [[ -z "$TITLE" ]] && fatal_error "Title is required in metadata file"

    log_info "Parsed metadata | Title: $TITLE | Tags: ${#LABELS_ARRAY[@]}"

    # Fetch existing PR state
    local pr_data=$(get_pr_data "$current_branch")
    PR_NUMBER=$(echo "$pr_data" | jq -r '.[0]?.number // empty')
    local pr_state=$(echo "$pr_data" | jq -r '.[0]?.state // empty')
    PR_URL=$(echo "$pr_data" | jq -r '.[0]?.url // empty')

    # Enforce Pre-PR CI Gating
    wait_for_ci_completion "$repo" "$current_branch"

    if [[ -n "$PR_NUMBER" ]]; then
        log_success "Found existing Pull Request #$PR_NUMBER ($pr_state)"
        if [[ "$pr_state" == "CLOSED" ]]; then
            gh pr reopen "$PR_NUMBER" >/dev/null 2>&1 && log_success "Reopened PR #$PR_NUMBER" || log_error "Failed to reopen PR #$PR_NUMBER"
        fi
    else
        log_info "No existing PR found."
    fi

    local dynamic_content=$(generate_dynamic_metadata "$MILESTONE" "$TITLE" "$current_branch" "$LINKED_ISSUE" "$PR_NUMBER" "$PR_URL")
    local author_section=$(generate_author_section)
    local body_content=$(awk '/^---$/{f++; next} f==2' "$metadata_file")

    # ============================================================
    # FIXED: using a temporary file to handle multiline replacement
    # ============================================================
    local temp_dynamic=$(mktemp)
    printf '%s\n' "$dynamic_content" > "$temp_dynamic"
    local full_body=$(echo "$body_content" | sed -e "/{{DYNAMIC_METADATA}}/ {
        r $temp_dynamic
        d
    }")
    rm -f "$temp_dynamic"

    full_body="${full_body}${author_section}"

    if [[ -z "$PR_NUMBER" ]]; then
        log_info "Creating new PR..."
        PR_URL=$(gh pr create --title "$TITLE" --body "$full_body" --base "$TARGET_BRANCH" --head "$current_branch" 2>/dev/null || echo "")

        if [[ -z "$PR_URL" ]]; then
            fatal_error "Failed to create PR. Ensure no unpushed commits and valid branches."
        fi

        PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$' || echo "")
        log_success "Created PR: $PR_URL"
    else
        log_info "Updating PR #$PR_NUMBER..."
        gh pr edit "$PR_NUMBER" --title "$TITLE" --body "$full_body" >/dev/null 2>&1 \
            && log_success "Updated PR: $PR_URL" \
            || log_error "Failed to update PR body/title."
    fi

    # Post-PR Operations
    process_labels "$PR_NUMBER" "$repo" "${LABELS_ARRAY[@]}"
    process_milestone "$PR_NUMBER" "$MILESTONE"
    process_people "$PR_NUMBER" "--add-assignee" "Assignee" "${ASSIGNEES_ARRAY[@]}"
    process_people "$PR_NUMBER" "--add-reviewer" "Reviewer" "${REVIEWERS_ARRAY[@]}"

    print_progress_bar
    print_summary
    print_signature

    local end_time=$(date +%s)
    echo -e "\n${WHITE}⏱ Completed in $((end_time - start_time)) seconds${NC}"

    if [[ $COUNT_FAIL -gt 0 ]]; then
        echo -e "\n${RED}❌ PR processing completed with errors. Check the logs above.${NC}"
    else
        echo -e "\n${GREEN}🎉 Feature Pull Request processed successfully! View it at: $PR_URL${NC}"
    fi
}

main "$@"
