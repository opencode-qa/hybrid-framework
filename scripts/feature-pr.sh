#!/usr/bin/env bash
set -eo pipefail

# === Configuration Constants ===
readonly TARGET_BRANCH="dev"
readonly METADATA_DIR=".github/features"
readonly MAX_CI_RETRIES=10
readonly CI_RETRY_DELAY=10  # seconds
readonly LABEL_COLOR="0366d6"
readonly REQUIRED_FIELDS=("title" "labels")
readonly CI_CHECK_ENABLED=true  # Set to false to skip CI checks

# === ANSI Color Codes ===
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
readonly ICON_ADD="${PURPLE}+${NC}"
readonly ICON_UPDATE="${CYAN}↻${NC}"

# === Global Variables ===
declare -A CHECKS_COUNT=( ["pass"]=0 ["warn"]=0 ["fail"]=0 ["info"]=0 ["skip"]=0 )
declare -a CHECK_RESULTS
declare -g PR_URL="" PR_NUMBER=""
declare -g TITLE="" MILESTONE="" LINKED_ISSUE="" ASSIGNEES="" REVIEWERS="" LABELS=""

# === Helper Functions ===

log_info() {
    echo -e "${ICON_INFO} ${BLUE}$1${NC}" >&2
    CHECKS_COUNT[info]=$((CHECKS_COUNT[info]+1))
    CHECK_RESULTS+=("info")
}

log_warn() {
    echo -e "${ICON_WARN} ${ORANGE}$1${NC}" >&2
    CHECKS_COUNT[warn]=$((CHECKS_COUNT[warn]+1))
    CHECK_RESULTS+=("warn")
}

log_success() {
    echo -e "${ICON_PASS} ${GREEN}$1${NC}" >&2
    CHECKS_COUNT[pass]=$((CHECKS_COUNT[pass]+1))
    CHECK_RESULTS+=("pass")
}

log_error() {
    echo -e "${ICON_FAIL} ${RED}$1${NC}" >&2
    CHECKS_COUNT[fail]=$((CHECKS_COUNT[fail]+1))
    CHECK_RESULTS+=("fail")
    exit 1
}

log_skip() {
    echo -e "${ICON_SKIP} ${WHITE}$1${NC}" >&2
    CHECKS_COUNT[skip]=$((CHECKS_COUNT[skip]+1))
    CHECK_RESULTS+=("skip")
}

validate_required() {
    local value="$1"
    local field="$2"

    if [[ -z "$value" ]]; then
        log_error "Required field '$field' is missing or empty in metadata"
    fi
}

validate_required_tools() {
    local required_tools=("gh" "jq" "git" "yq")
    local missing_tools=()

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
    fi

    log_success "All required tools are available"
}

clean_array_input() {
    echo "$1" | sed -E 's/[][]//g; s/[,"'\'']/ /g; s/  */ /g; s/^[[:space:]]*//; s/[[:space:]]*$//'
}

get_yaml_value() {
    local field=$1
    local file=$2
    local yaml_content
    yaml_content=$(awk '/^---$/{if (++n == 1) next; else exit} n' "$file")
    echo "$yaml_content" | yq eval ".${field}" - 2>/dev/null || echo ""
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
    local pr_data
    pr_data=$(gh pr list --head "$branch" --base "$TARGET_BRANCH" \
        --json number,state,url,labels,assignees,reviewRequests,milestone --limit 1)
    [[ -z "$pr_data" ]] && echo "[]" || echo "$pr_data"
}

wait_for_ci_completion() {
    if [[ "$CI_CHECK_ENABLED" != "true" ]]; then
        log_skip "CI checks are disabled"
        return 0
    fi

    local repo=$1
    local branch=$2
    local attempts=0

    log_info "Checking GitHub Actions status..."

    while [[ $attempts -lt $MAX_CI_RETRIES ]]; do
        local status_data
        status_data=$(gh api "repos/$repo/actions/runs?branch=$branch&per_page=1" -q '.workflow_runs[0] // null')

        if [[ "$status_data" == "null" ]]; then
            log_warn "No CI runs found for branch $branch"
            return 0
        fi

        local status=$(jq -r '.status' <<< "$status_data")
        local conclusion=$(jq -r '.conclusion' <<< "$status_data")

        case "$status-$conclusion" in
            "completed-success")
                log_success "CI checks passed successfully"
                return 0
                ;;
            "completed-"*)
                log_error "CI checks failed with conclusion: $conclusion"
                ;;
            *)
                log_info "CI status: ${status:-unknown} (attempt $((attempts+1))/$MAX_CI_RETRIES)"
                sleep $CI_RETRY_DELAY
                ;;
        esac

        attempts=$((attempts+1))
    done

    log_warn "CI did not complete within the expected time"
    return 0
}

generate_dynamic_metadata() {
    local milestone=$1
    local title=$2
    local current_branch=$3
    local linked_issue=$4

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

    if [[ -n "$PR_NUMBER" ]]; then
        echo "## 🔀 Merged PRs"
        echo "- ✅ [#${PR_NUMBER}](${PR_URL}) – \`${current_branch} → ${TARGET_BRANCH}\`: ${title}"
    fi
}

generate_author_section() {
    cat <<EOF

## 👤 Author
**[Anuj Kumar](https://www.linkedin.com/in/anuj-kumar-qa/)"
🏅 QA Consultant & Test Automation Engineer
EOF
}

process_labels() {
    local pr_num=$1
    local repo=$2
    local desired_labels=$3
    local existing_labels=$4

    log_info "Processing labels..."
    local current_repo_labels
    current_repo_labels=$(gh api "repos/$repo/labels" --jq '.[].name' | tr '\n' ',')

    for label in $desired_labels; do
        if [[ ",${existing_labels}," == *",${label},"* ]]; then
            log_skip "Label '$label' already exists on PR"
            continue
        fi

        if [[ ",${current_repo_labels}," != *",${label},"* ]]; then
            log_info "Creating label '$label'"
            gh label create "$label" --color "$LABEL_COLOR" --description "Automatically created" \
                || log_warn "Failed to create label '$label'"
            continue
        fi

        log_info "Adding label '$label' to PR"
        gh pr edit "$pr_num" --add-label "$label" >/dev/null \
            && log_success "Added label '$label'" \
            || log_warn "Failed to add label '$label'"
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
    current_milestone=$(gh pr view "$pr_num" --json milestone -q '.milestone.title // empty')

    if [[ "$current_milestone" == "$desired_milestone" ]]; then
        log_skip "Milestone '$desired_milestone' already set"
    else
        log_info "Setting milestone '$desired_milestone'"
        gh pr edit "$pr_num" --milestone "$desired_milestone" \
            && log_success "Milestone set to '$desired_milestone'" \
            || log_warn "Failed to set milestone '$desired_milestone'"
    fi
}

process_assignees() {
    local pr_num=$1
    local desired_assignees=$2
    local existing_assignees=$3

    if [[ -z "$desired_assignees" ]]; then
        log_skip "No assignees specified in metadata"
        return
    fi

    log_info "Processing assignees..."
    for assignee in $desired_assignees; do
        if [[ ",${existing_assignees}," == *",${assignee},"* ]]; then
            log_skip "Assignee '$assignee' already assigned"
        else
            log_info "Assigning '$assignee'"
            gh pr edit "$pr_num" --add-assignee "$assignee" \
                && log_success "Assigned '$assignee'" \
                || log_warn "Failed to assign '$assignee'"
        fi
    done
}

process_reviewers() {
    local pr_num=$1
    local desired_reviewers=$2
    local existing_reviewers=$3

    if [[ -z "$desired_reviewers" ]]; then
        log_skip "No reviewers specified in metadata"
        return
    fi

    log_info "Processing reviewers..."
    for reviewer in $desired_reviewers; do
        if [[ ",${existing_reviewers}," == *",${reviewer},"* ]]; then
            log_skip "Reviewer '$reviewer' already requested"
        else
            log_info "Requesting review from '$reviewer'"
            gh pr edit "$pr_num" --add-reviewer "$reviewer" \
                && log_success "Review requested from '$reviewer'" \
                || log_warn "Failed to request review from '$reviewer'"
        fi
    done
}

validate_metadata_content() {
    local metadata_file="$1"

    for field in "${REQUIRED_FIELDS[@]}"; do
        local value
        case "$field" in
            "title") value="$TITLE" ;;
            "labels") value="$LABELS" ;;
            *) value=$(get_yaml_value "$field" "$metadata_file") ;;
        esac
        validate_required "$value" "$field"
    done

    if [[ "$TITLE" == "Untitled PR" ]]; then
        log_error "Title must be specified in metadata file"
    fi

    log_success "Metadata validation passed"
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

    echo -e "\nProgress: [${filled_bar}] 100% (${total_checks}/$total_checks checks)"
}

print_summary() {
    echo -e "\n${WHITE}📊 Validation Summary:${NC}"
    printf "  ${ICON_PASS} Passed    ${GREEN}🟢  ⇒ %2d\n" "${CHECKS_COUNT[pass]}"
    printf "  ${ICON_WARN} Warnings  ${ORANGE}🟠  ⇒ %2d\n" "${CHECKS_COUNT[warn]}"
    printf "  ${ICON_FAIL} Failures  ${RED}🔴  ⇒ %2d\n" "${CHECKS_COUNT[fail]}"
    printf "  ${ICON_INFO} Info      ${BLUE}🔵  ⇒ %2d\n" "${CHECKS_COUNT[info]}"
    printf "  ${ICON_SKIP} Skipped   ${WHITE}⚫  ⇒ %2d\n" "${CHECKS_COUNT[skip]}"
}

main() {
    local start_time=$(date +%s)
    local current_branch=$(get_current_branch)
    local branch_key="${current_branch#feature/}"
    local metadata_file="${METADATA_DIR}/${branch_key}.md"
    local repo=$(get_repo_name)

    log_info "Current branch detected: ${current_branch}"
    log_info "Target branch for PR: ${TARGET_BRANCH}"

    [[ -f "$metadata_file" ]] || log_error "Metadata file not found: $metadata_file"
    log_success "Found metadata file: $metadata_file"

    TITLE=$(get_yaml_value "title" "$metadata_file")
    LINKED_ISSUE=$(get_yaml_value "linked_issue" "$metadata_file")
    MILESTONE=$(get_yaml_value "milestone" "$metadata_file")
    ASSIGNEES=$(clean_array_input "$(get_yaml_value "assignees" "$metadata_file")")
    REVIEWERS=$(clean_array_input "$(get_yaml_value "reviewers" "$metadata_file")")
    LABELS=$(clean_array_input "$(get_yaml_value "labels" "$metadata_file")")

    validate_metadata_content "$metadata_file"

    log_info "Parsed metadata:"
    log_info "Title: $TITLE"
    log_info "Milestone: ${MILESTONE:-none}"
    log_info "Linked Issue: ${LINKED_ISSUE:-none}"
    log_info "Assignees: ${ASSIGNEES:-none}"
    log_info "Reviewers: ${REVIEWERS:-none}"
    log_info "Labels: ${LABELS:-none}"

    local pr_data=$(get_pr_data "$current_branch")
    PR_NUMBER=$(jq -r '.[0]?.number // empty' <<< "$pr_data")
    local pr_state=$(jq -r '.[0]?.state // empty' <<< "$pr_data")
    PR_URL=$(jq -r '.[0]?.url // empty' <<< "$pr_data")
    local existing_labels=$(jq -r '.[0]?.labels // [] | map(.name) | join(",")' <<< "$pr_data")
    local existing_assignees=$(jq -r '.[0]?.assignees // [] | map(.login) | join(",")' <<< "$pr_data")
    local existing_reviewers=$(jq -r '.[0]?.reviewRequests // [] | map(.login) | join(",")' <<< "$pr_data")

    if [[ -n "$PR_NUMBER" ]]; then
        log_success "Found existing Pull Request #$PR_NUMBER ($pr_state)"
        [[ "$pr_state" == "closed" ]] && gh pr reopen "$PR_NUMBER" && log_success "Reopened PR #$PR_NUMBER"
    else
        log_info "No existing PR found"
    fi

    wait_for_ci_completion "$repo" "$current_branch"

    local dynamic_content=$(generate_dynamic_metadata "$MILESTONE" "$TITLE" "$current_branch" "$LINKED_ISSUE")
    local author_section=$(generate_author_section)
    local body_content=$(awk '/^---$/{f++; next} f==2' "$metadata_file")
    local full_body="${body_content//\{\{DYNAMIC_METADATA\}\}/$dynamic_content}$author_section"

    if [[ -z "$PR_NUMBER" ]]; then
        log_info "Creating new PR..."
        PR_URL=$(gh pr create --title "$TITLE" --body "$full_body" --base "$TARGET_BRANCH" --head "$current_branch")
        PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')
        log_success "Created PR: $PR_URL"
    else
        log_info "Updating PR #$PR_NUMBER..."
        gh pr edit "$PR_NUMBER" --title "$TITLE" --body "$full_body"
        log_success "Updated PR: $PR_URL"
    fi

    process_labels "$PR_NUMBER" "$repo" "$LABELS" "$existing_labels"
    process_milestone "$PR_NUMBER" "$MILESTONE"
    process_assignees "$PR_NUMBER" "$ASSIGNEES" "$existing_assignees"
    process_reviewers "$PR_NUMBER" "$REVIEWERS" "$existing_reviewers"

    print_progress_bar
    print_summary

    local end_time=$(date +%s)
    echo -e "\n${WHITE}⏱ Completed in $((end_time - start_time)) seconds${NC}"

    if [[ ${CHECKS_COUNT[fail]} -gt 0 ]]; then
        log_error "❌ PR processing completed with errors"
    else
        log_success "🎉 Feature Pull Request processed successfully! View it at: $PR_URL"
    fi
}

validate_required_tools
main "$@"
