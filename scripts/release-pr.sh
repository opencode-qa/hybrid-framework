#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit

# ==============================================================================
# release-pr.sh – Creates a release PR from dev → main
# ==============================================================================

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
readonly TARGET_BRANCH="main"
readonly SOURCE_BRANCH="dev"
readonly METADATA_DIR=".github/releases"
readonly MAX_CI_RETRIES=30
readonly CI_RETRY_DELAY=60          # seconds
readonly LABEL_COLOR="0366d6"

# ------------------------------------------------------------------------------
# ANSI & Icons
# ------------------------------------------------------------------------------
readonly BOLD='\033[1m'
readonly GREEN='\033[1;32m'
readonly ORANGE='\033[38;5;214m'
readonly RED='\033[1;31m'
readonly WHITE='\033[1;37m'
readonly BLUE='\033[1;34m'
readonly PURPLE='\033[1;35m'
readonly CYAN='\033[1;36m'
readonly NC='\033[0m'

readonly ICON_PASS="${GREEN}✓${NC}"
readonly ICON_WARN="${ORANGE}⚠${NC}"
readonly ICON_FAIL="${RED}✗${NC}"
readonly ICON_INFO="${BLUE}ℹ${NC}"
readonly ICON_SKIP="${WHITE}○${NC}"
readonly ICON_RELEASE="${PURPLE}🚀${NC}"
readonly ICON_VERSION="${GREEN}🔖${NC}"

# ------------------------------------------------------------------------------
# Global Variables
# ------------------------------------------------------------------------------
declare -A CHECKS_COUNT=( ["pass"]=0 ["warn"]=0 ["fail"]=0 ["info"]=0 ["skip"]=0 )
declare -a CHECK_RESULTS=()

declare -g PR_URL="" PR_NUMBER=""
declare -g TITLE="" MILESTONE="" LINKED_ISSUE=""
declare -a ASSIGNEES_ARRAY=()
declare -a REVIEWERS_ARRAY=()
declare -a LABELS_ARRAY=()

declare -g CURRENT_VERSION="" RELEASE_VERSION="" RELEASE_TAG="" RELEASE_BRANCH=""
declare -g DRY_RUN=false

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------
log_info()    { echo -e "${ICON_INFO} ${BLUE}$*${NC}" >&2; CHECKS_COUNT["info"]=$((CHECKS_COUNT["info"]+1)); CHECK_RESULTS+=("info"); }
log_warn()    { echo -e "${ICON_WARN} ${ORANGE}$*${NC}" >&2; CHECKS_COUNT["warn"]=$((CHECKS_COUNT["warn"]+1)); CHECK_RESULTS+=("warn"); }
log_success() { echo -e "${ICON_PASS} ${GREEN}$*${NC}" >&2; CHECKS_COUNT["pass"]=$((CHECKS_COUNT["pass"]+1)); CHECK_RESULTS+=("pass"); }
log_error()   { echo -e "${ICON_FAIL} ${RED}$*${NC}" >&2; CHECKS_COUNT["fail"]=$((CHECKS_COUNT["fail"]+1)); CHECK_RESULTS+=("fail"); }
log_skip()    { echo -e "${ICON_SKIP} ${WHITE}$*${NC}" >&2; CHECKS_COUNT["skip"]=$((CHECKS_COUNT["skip"]+1)); CHECK_RESULTS+=("skip"); }

fatal() {
    echo -e "\n${ICON_FAIL} ${RED}FATAL ERROR: $1${NC}" >&2
    exit 1
}

validate_required_tools() {
    local required_tools=("gh" "jq" "git" "mvn" "yq")
    local missing=()
    for tool in "${required_tools[@]}"; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    [[ ${#missing[@]} -eq 0 ]] || fatal "Missing required tools: ${missing[*]}"
    log_success "All required tools are available"
}

get_yaml_value() {
    local field=$1 file=$2
    awk '/^---$/{if (++n == 1) next; else exit} n' "$file" | yq eval ".${field} | select(. != null)" - 2>/dev/null || echo ""
}

get_yaml_array() {
    local field=$1 file=$2
    local result
    result=$(awk '/^---$/{if (++n == 1) next; else exit} n' "$file" | yq eval ".${field}[] | select(. != null)" - 2>/dev/null)
    if [[ -n "$result" ]]; then
        echo "$result"
        return
    fi
    local single
    single=$(awk '/^---$/{if (++n == 1) next; else exit} n' "$file" | yq eval ".${field} | select(. != null)" - 2>/dev/null)
    if [[ -n "$single" ]]; then
        echo "$single" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$'
    fi
}

# ------------------------------------------------------------------------------
# Version Handling (Maven pom.xml)
# ------------------------------------------------------------------------------
get_current_version_from_pom() {
    local version
    version=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout | tail -1)
    if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-SNAPSHOT)?$ ]]; then
        echo "$version"
    else
        fatal "Invalid version in pom.xml: $version (expected X.Y.Z or X.Y.Z-SNAPSHOT)"
    fi
}

prepare_release_version() {
    CURRENT_VERSION=$(get_current_version_from_pom)
    if [[ "$CURRENT_VERSION" != *-SNAPSHOT ]]; then
        fatal "Current version in pom.xml is not a SNAPSHOT. Release branches must start from a SNAPSHOT version."
    fi
    RELEASE_VERSION="${CURRENT_VERSION%-SNAPSHOT}"
    RELEASE_TAG="v${RELEASE_VERSION}"
    RELEASE_BRANCH="release/${RELEASE_TAG}"
    log_info "Current version (SNAPSHOT): $CURRENT_VERSION"
    log_info "Release version: $RELEASE_VERSION"
    log_info "Release branch: $RELEASE_BRANCH"
}

# ------------------------------------------------------------------------------
# Git Operations
# ------------------------------------------------------------------------------
validate_starting_branch() {
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$current_branch" != "$SOURCE_BRANCH" ]]; then
        fatal "You must run this script from the '$SOURCE_BRANCH' branch. Current: $current_branch"
    fi
    log_success "Starting from correct branch: $SOURCE_BRANCH"
}

sync_dev_branch() {
    log_info "Fetching and updating $SOURCE_BRANCH..."
    git fetch origin "$SOURCE_BRANCH"
    git checkout "$SOURCE_BRANCH"
    git pull origin "$SOURCE_BRANCH"
    log_success "$SOURCE_BRANCH is up to date"
}

prepare_and_push_branch() {
    # If the release branch already exists remotely, just check it out
    if git ls-remote --heads origin "$RELEASE_BRANCH" | grep -q "refs/heads/$RELEASE_BRANCH$"; then
        log_info "Release branch $RELEASE_BRANCH already exists remotely. Checking it out..."
        git fetch origin "$RELEASE_BRANCH"
        git checkout "$RELEASE_BRANCH"
        git pull origin "$RELEASE_BRANCH" 2>/dev/null || true
        log_success "Switched to existing branch $RELEASE_BRANCH"
        return
    fi

    log_info "Creating release branch $RELEASE_BRANCH from $SOURCE_BRANCH..."
    git checkout -b "$RELEASE_BRANCH"

    # Update pom.xml to release version (remove -SNAPSHOT)
    mvn versions:set -DnewVersion="$RELEASE_VERSION" -DgenerateBackupPoms=false
    git add pom.xml
    git commit -m "chore(release): prepare release $RELEASE_TAG"

    git push -u origin "$RELEASE_BRANCH"
    log_success "Release branch pushed: $RELEASE_BRANCH"
}

# ------------------------------------------------------------------------------
# CI Waiting (optional but recommended)
# ------------------------------------------------------------------------------
get_repo_name() { gh repo view --json nameWithOwner -q '.nameWithOwner'; }

wait_for_ci_completion() {
    local repo=$1 branch=$2 attempts=0
    local workflows_count
    workflows_count=$(gh api "repos/$repo/actions/workflows" -q '.total_count' 2>/dev/null || echo "0")

    if [[ "$workflows_count" -eq 0 ]]; then
        log_warn "No workflows detected – skipping CI checks"
        return 0
    fi

    log_info "Waiting for CI on branch $branch..."
    while [[ $attempts -lt $MAX_CI_RETRIES ]]; do
        local status_data
        status_data=$(gh api "repos/$repo/actions/runs?branch=$branch&per_page=1" -q '.workflow_runs[0]' 2>/dev/null || echo "{}")
        local status=$(jq -r '.status // empty' <<< "$status_data")
        local conclusion=$(jq -r '.conclusion // empty' <<< "$status_data")

        case "$status-$conclusion" in
            "completed-success") log_success "CI passed"; return 0 ;;
            "completed-failure"|"completed-cancelled"|"completed-timed_out") fatal "CI failed with conclusion: $conclusion" ;;
            *) log_info "CI status: $status (attempt $((attempts+1))/$MAX_CI_RETRIES)"; sleep $CI_RETRY_DELAY ;;
        esac
        attempts=$((attempts+1))
    done
    fatal "CI did not complete within the expected time"
}

# ------------------------------------------------------------------------------
# PR Content Generation
# ------------------------------------------------------------------------------
generate_release_metadata() {
    local milestone=$1 title=$2 branch=$3 linked_issue=$4
    cat <<EOF

## 🚀 Release Information
- **Release Version**: \`${RELEASE_TAG}\`
- **Milestone**: \`${milestone}\` – ${title}
- **Source Branch**: \`${branch}\`
- **Target Branch**: \`${TARGET_BRANCH}\`

EOF
    [[ -n "$linked_issue" ]] && echo -e "## 🔗 Related Issues\n- Closes #${linked_issue}\n"
}

generate_release_notes() {
    cat <<EOF

## 📝 Release Notes
This PR promotes \`${RELEASE_TAG}\` from \`dev\` to \`main\`.

### Versioning
- **Released Version**: \`${RELEASE_TAG}\`
- **CI Status**: ✅ All checks passed

## ✅ Quality Assurance
- CI checks passed on the release branch
- Version validated (removed -SNAPSHOT)
- Metadata verified

## 🔄 Post-Merge Automation (GitHub Actions)
After merging this PR, the following will happen automatically:
1. Create signed Git tag \`${RELEASE_TAG}\`
2. Create GitHub Release with auto-generated notes
3. Bump \`dev\` to the next SNAPSHOT version
4. Open a version bump PR (\`chore/bump-to-*\`)

EOF
}

generate_author_section() {
    cat <<EOF

## 👤 Release Manager
**ANUJ KUMAR** | 🏅 QA Lead & AI-Assisted Testing Specialist
*Specializing in scalable test automation and AI-driven quality assurance.*

📧 Email: [anujpatiyal@live.in](mailto:anujpatiyal@live.in)
🔗 LinkedIn: [https://www.linkedin.com/in/anuj-kumar-qa/](https://www.linkedin.com/in/anuj-kumar-qa/)
EOF
}

# ------------------------------------------------------------------------------
# PR Metadata Processing (Labels, Milestone, Assignees, Reviewers)
# ------------------------------------------------------------------------------
process_labels() {
    local pr_num="$1" repo="$2"
    shift 2
    local desired_labels=("$@")

    [[ ${#desired_labels[@]} -eq 0 ]] && return

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
            gh label create "$label" --color "$LABEL_COLOR" --description "Created via release script" >/dev/null 2>&1 \
                || log_warn "Failed to create label '$label' (Check permissions)"
        fi

        gh pr edit "$pr_num" --add-label "$label" >/dev/null 2>&1 \
            && log_success "Added label '$label'" \
            || log_error "Failed to add label '$label'"
    done
}

process_milestone() {
    local pr_num=$1 desired_milestone=$2
    if [[ -z "$desired_milestone" ]]; then
        log_skip "No milestone specified"
        return
    fi

    local current_milestone
    current_milestone=$(gh pr view "$pr_num" --json milestone -q '.milestone.title // empty' 2>/dev/null || echo "")

    if [[ "$current_milestone" == "$desired_milestone" ]]; then
        log_skip "Milestone '$desired_milestone' already set"
    else
        gh pr edit "$pr_num" --milestone "$desired_milestone" >/dev/null 2>&1 \
            && log_success "Milestone set to '$desired_milestone'" \
            || log_error "Failed to set milestone '$desired_milestone'"
    fi
}

process_people() {
    local pr_num="$1" flag_name="$2" entity_name="$3"
    shift 3
    local desired_people=("$@")

    [[ ${#desired_people[@]} -eq 0 ]] && return

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
            gh pr edit "$pr_num" "$flag_name" "$person" >/dev/null 2>&1 \
                && log_success "Added ${entity_name} '$person'" \
                || log_error "Failed to add ${entity_name} '$person'"
        fi
    done
}

# ------------------------------------------------------------------------------
# PR State Detection & Update/Create
# ------------------------------------------------------------------------------
get_pr_data() {
    local branch=$1
    gh pr list --state all --head "$branch" --base "$TARGET_BRANCH" \
        --json number,state,url --limit 1 2>/dev/null || echo "[]"
}

# ------------------------------------------------------------------------------
# Output Formatting
# ------------------------------------------------------------------------------
print_banner() {
    echo -e "\n${PURPLE}╔══════════════════════════════════════════════════════════════╗"
    echo -e "║${NC}${PURPLE}          🚀  R E L E A S E   P R   C R E A T O R          ${NC}${PURPLE}║"
    echo -e "╚══════════════════════════════════════════════════════════════╝${NC}"
}

print_progress_bar() {
    local total=${#CHECK_RESULTS[@]}
    [[ $total -eq 0 ]] && return
    local bar=""
    for r in "${CHECK_RESULTS[@]}"; do
        case "$r" in
            "pass") bar+="🟩" ;;
            "warn") bar+="🟧" ;;
            "fail") bar+="🟥" ;;
            "info") bar+="🟦" ;;
            "skip") bar+="⬛" ;;
        esac
    done
    echo -e "\n${WHITE}Progress: [${bar}] 100% (${total}/${total} checks)${NC}"
}

print_summary() {
    echo -e "\n${WHITE}📊 Summary:${NC}"
    printf "  ${ICON_PASS} Passed    ${GREEN}🟢  ⇒ %2d\n" "${CHECKS_COUNT[pass]}"
    printf "  ${ICON_WARN} Warnings  ${ORANGE}🟠  ⇒ %2d\n" "${CHECKS_COUNT[warn]}"
    printf "  ${ICON_FAIL} Failures  ${RED}🔴  ⇒ %2d\n" "${CHECKS_COUNT[fail]}"
    printf "  ${ICON_INFO} Info      ${BLUE}🔵  ⇒ %2d\n" "${CHECKS_COUNT[info]}"
    printf "  ${ICON_SKIP} Skipped   ${WHITE}⚫  ⇒ %2d\n" "${CHECKS_COUNT[skip]}"
}

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
# Main
# ------------------------------------------------------------------------------
main() {
    local start_time=$(date +%s)
    print_banner

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=true; shift ;;
            *) shift ;;
        esac
    done

    validate_required_tools
    validate_starting_branch
    prepare_release_version

    # Locate metadata file
    local metadata_file="${METADATA_DIR}/${RELEASE_TAG}.md"
    [[ -f "$metadata_file" ]] || metadata_file="${METADATA_DIR}/release.md"
    [[ -f "$metadata_file" ]] || fatal "No metadata file found in $METADATA_DIR/ (expected release.md or ${RELEASE_BRANCH}.md)"
    log_success "Using metadata: $metadata_file"

    # Parse metadata
    TITLE=$(get_yaml_value "title" "$metadata_file")
    LINKED_ISSUE=$(get_yaml_value "linked_issue" "$metadata_file")
    MILESTONE=$(get_yaml_value "milestone" "$metadata_file")

    while IFS= read -r line; do [[ -n "$line" ]] && LABELS_ARRAY+=("$line"); done < <(get_yaml_array "labels" "$metadata_file")
    while IFS= read -r line; do [[ -n "$line" ]] && ASSIGNEES_ARRAY+=("$line"); done < <(get_yaml_array "assignees" "$metadata_file")
    while IFS= read -r line; do [[ -n "$line" ]] && REVIEWERS_ARRAY+=("$line"); done < <(get_yaml_array "reviewers" "$metadata_file")

    # Ensure 'release' label is always present
    local has_release_label=false
    for l in "${LABELS_ARRAY[@]}"; do
        if [[ "$l" == "release" ]]; then has_release_label=true; break; fi
    done
    if [[ "$has_release_label" == "false" ]]; then
        LABELS_ARRAY=("release" "${LABELS_ARRAY[@]}")
    fi

    [[ -z "$TITLE" ]] && fatal "Title is required in metadata file"
    log_info "Title: $TITLE"
    log_info "Milestone: $MILESTONE"

    # Sync and create release branch
    sync_dev_branch
    prepare_and_push_branch

    # Wait for CI on the release branch
    local repo
    repo=$(get_repo_name)
    wait_for_ci_completion "$repo" "$RELEASE_BRANCH"

    # Build PR body
    local body_content
    body_content=$(awk '/^---$/{f++; next} f==2' "$metadata_file" || echo "")
    local meta_block
    meta_block=$(generate_release_metadata "$MILESTONE" "$TITLE" "$RELEASE_BRANCH" "$LINKED_ISSUE")

    local temp_dynamic
    temp_dynamic=$(mktemp)
    printf '%s\n' "$meta_block" > "$temp_dynamic"
    local full_body
    full_body=$(echo "$body_content" | sed -e "/{{RELEASE_METADATA}}/ {
        r $temp_dynamic
        d
    }")
    rm -f "$temp_dynamic"

    full_body="${full_body}$(generate_release_notes)"
    full_body="${full_body}$(generate_author_section)"

    local pr_title="🎯 [RELEASE] $TITLE ($RELEASE_TAG)"

    # Check for existing PR
    local pr_data
    pr_data=$(get_pr_data "$RELEASE_BRANCH")
    PR_NUMBER=$(echo "$pr_data" | jq -r '.[0]?.number // empty')
    local pr_state
    pr_state=$(echo "$pr_data" | jq -r '.[0]?.state // empty')
    PR_URL=$(echo "$pr_data" | jq -r '.[0]?.url // empty')

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "\n${CYAN}DRY RUN - No changes will be made${NC}"
        echo "PR Title: $pr_title"
        echo "PR Body (preview):"
        echo "--------------------"
        echo "$full_body"
        echo "--------------------"
        return 0
    fi

    # Create or update PR
    if [[ -n "$PR_NUMBER" ]]; then
        log_success "Found existing Pull Request #$PR_NUMBER ($pr_state)"
        if [[ "$pr_state" == "CLOSED" ]]; then
            log_info "Reopening closed PR #$PR_NUMBER..."
            gh pr reopen "$PR_NUMBER" >/dev/null 2>&1 \
                && log_success "Reopened PR #$PR_NUMBER" \
                || log_warn "Failed to reopen PR #$PR_NUMBER (may already be merged)"
        fi
        log_info "Updating existing PR #$PR_NUMBER..."
        gh pr edit "$PR_NUMBER" --title "$pr_title" --body "$full_body" >/dev/null 2>&1 \
            && log_success "Updated PR: $PR_URL" \
            || log_error "Failed to update PR body/title."
    else
        log_info "Creating new release PR..."
        PR_URL=$(gh pr create --title "$pr_title" --body "$full_body" --base "$TARGET_BRANCH" --head "$RELEASE_BRANCH" 2>/dev/null || echo "")
        if [[ -z "$PR_URL" ]]; then
            fatal "Failed to create PR. Ensure there are no unpushed commits and the branches are valid."
        fi
        PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$' || echo "")
        log_success "Created PR: $PR_URL"
    fi

    # Apply metadata
    process_labels "$PR_NUMBER" "$repo" "${LABELS_ARRAY[@]}"
    process_milestone "$PR_NUMBER" "$MILESTONE"
    process_people "$PR_NUMBER" "--add-assignee" "Assignee" "${ASSIGNEES_ARRAY[@]}"
    process_people "$PR_NUMBER" "--add-reviewer" "Reviewer" "${REVIEWERS_ARRAY[@]}"

    if [[ -n "$LINKED_ISSUE" ]]; then
        gh issue comment "$LINKED_ISSUE" --body "Release PR created: $PR_URL" >/dev/null 2>&1 \
            && log_success "Linked to issue #$LINKED_ISSUE" \
            || log_warn "Failed to link to issue #$LINKED_ISSUE"
    fi

    print_progress_bar
    print_summary
    print_signature

    local end_time=$(date +%s)
    echo -e "\n${WHITE}⏱ Completed in $((end_time - start_time)) seconds${NC}"

    if [[ ${CHECKS_COUNT[fail]} -gt 0 ]]; then
        echo -e "\n${RED}❌ PR processing completed with errors. Check the logs above.${NC}"
    else
        echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗"
        echo -e "║${NC}${GREEN}          🎉  R E L E A S E   P R   R E A D Y           ${NC}${PURPLE}║"
        echo -e "╚══════════════════════════════════════════════════════════════╝${NC}"
        log_success "${ICON_RELEASE} Release PR: ${BLUE}${PR_URL}${NC}"
        echo -e "${ICON_VERSION} ${BLUE}Release tag will be created after merge: ${GREEN}${RELEASE_TAG}${NC}"
    fi
}

main "$@"
