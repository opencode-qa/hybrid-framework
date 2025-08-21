#!/usr/bin/env bash
set -eo pipefail

# === Configuration Constants ===
readonly TARGET_BRANCH="main"
readonly METADATA_DIR=".github/releases"
readonly MAX_CI_RETRIES=10
readonly CI_RETRY_DELAY=10  # seconds
readonly LABEL_COLOR="0366d6"
readonly REQUIRED_FIELDS=("title" "labels" "milestone")

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
readonly ICON_RELEASE="${PURPLE}🚀${NC}"
readonly ICON_TAG="${BLUE}🏷️${NC}"
readonly ICON_VERSION="${GREEN}🔖${NC}"

# === Global Variables ===
declare -A CHECKS_COUNT=( ["pass"]=0 ["warn"]=0 ["fail"]=0 ["info"]=0 ["skip"]=0 )
declare -a CHECK_RESULTS
declare -g PR_URL="" PR_NUMBER="" CURRENT_VERSION="" NEXT_VERSION=""
declare -g TITLE="" MILESTONE="" LINKED_ISSUE="" ASSIGNEES="" REVIEWERS="" LABELS=""
declare -g IS_INITIAL_RELEASE=false

# CLI flags (defaults)
AUTO_VERSION_BUMP=${AUTO_VERSION_BUMP:-false}
DRY_RUN=${DRY_RUN:-false}

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
        log_error "Required field '$field' is missing or empty in release metadata"
    fi
}

validate_required_tools() {
    local required_tools=("gh" "jq" "git" "yq")
    local missing_tools=()

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
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

# === Version Functions ===

get_current_version() {
    # Get latest tag or default to v0.0.0
    CURRENT_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")

    # Special handling for initial release
    if [[ "$CURRENT_VERSION" == "v0.0.0" ]]; then
        IS_INITIAL_RELEASE=true
        log_info "Initial release detected (v0.0.0)"
    fi

    # Validate version format
    if [[ ! "$CURRENT_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid version format (expected vX.Y.Z): $CURRENT_VERSION"
    fi

    log_info "Current version detected: $CURRENT_VERSION"
}

get_next_version() {
    if $IS_INITIAL_RELEASE; then
        NEXT_VERSION="v0.1.0"  # First real version after initial release
        return
    fi

    local version="${CURRENT_VERSION#v}"
    IFS='.' read -r major minor patch <<< "$version"
    NEXT_VERSION="v${major}.$((minor+1)).0"
}

validate_version_increment() {
    if $IS_INITIAL_RELEASE; then
        log_skip "Version increment validation skipped for initial release"
        return
    fi

    if [[ "$CURRENT_VERSION" == "$NEXT_VERSION" ]]; then
        log_error "Version increment failed - current and next versions are identical"
    fi
    log_success "Version increment validated"
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
        --json number,state,url,labels,assignees,reviewRequests,milestone --limit 1 || echo "[]"
}

check_workflows_exist() {
    local repo=$1
    gh api "repos/$repo/actions/workflows" -q '.total_count'
}

wait_for_ci_completion() {
    local repo=$1
    local branch=$2
    local attempts=0

    # Skip CI check if no workflows exist
    if [[ $(check_workflows_exist "$repo") -eq 0 ]]; then
        log_warn "No workflows detected - skipping CI checks"
        return 0
    fi

    log_info "Checking GitHub Actions status for release branch..."

    while [[ $attempts -lt $MAX_CI_RETRIES ]]; do
        local status_data
        status_data=$(gh api "repos/$repo/actions/runs?branch=$branch&per_page=1" -q '.workflow_runs[0]' 2>/dev/null || echo "{}")

        local status=$(jq -r '.status // empty' <<< "$status_data")
        local conclusion=$(jq -r '.conclusion // empty' <<< "$status_data")

        case "$status-$conclusion" in
            "completed-success")
                log_success "Release CI checks passed successfully"
                return 0
                ;;
            "completed-"*)
                log_error "Release CI checks failed with conclusion: $conclusion"
                ;;
            *)
                log_info "Release CI status: $status (attempt $((attempts+1))/$MAX_CI_RETRIES)"
                sleep $CI_RETRY_DELAY
                ;;
        esac

        attempts=$((attempts+1))
    done

    log_error "Release CI did not complete within the expected time"
}

# === Metadata & Release Notes (updated to use explicit release_tag and next_dev) ===
# generate_release_metadata(release_milestone, title, current_branch, linked_issue, release_tag, next_dev)
generate_release_metadata() {
    local milestone=$1
    local title=$2
    local current_branch=$3
    local linked_issue=$4
    local release_tag=$5
    local next_dev=$6

    cat <<EOF

## 🚀 Release Information
- **Release Version**: \`${release_tag}\`
- **Next Development Version**: \`${next_dev}\`
- **Milestone**: \`${milestone}\` – ${title}
- **Source Branch**: \`${current_branch}\`
- **Target Branch**: \`${TARGET_BRANCH}\`

EOF

    if [[ -n "$linked_issue" ]]; then
        echo "## 🔗 Related Issues"
        echo "- Closes #${linked_issue}"
        echo
    fi
}

# generate_release_notes(release_tag, next_dev)
generate_release_notes() {
    local release_tag=$1
    local next_dev=$2

    cat <<EOF

## 📝 Release Notes
This release publishes \`${release_tag}\`. Key highlights:

- Automated release process execution
- CI/CD pipeline activation

### Versioning
- Released: \`${release_tag}\`
- Next development/snapshot version: \`${next_dev}\`

## ✅ Quality Assurance
- All CI checks passed successfully
- Version increment validated
- Release metadata verified

## 👤 Author
**ANUJ KUMAR** 🏅 QA Consultant & Test Automation Architect
- 📧 Email: [anujpatiyal@live.in](mailto:anujpatiyal@live.in)
- 🔗 [LinkedIn Profile](https://www.linkedin.com/in/anuj-kumar-qa/)
EOF
}

process_labels() {
    local pr_num=$1
    local repo=$2
    local desired_labels=$3
    local existing_labels=$4

    log_info "Processing release labels..."

    # Ensure release label is always present
    if [[ ! "$desired_labels" =~ (^| )release($| ) ]]; then
        desired_labels="release $desired_labels"
    fi

    local current_repo_labels
    current_repo_labels=$(gh api "repos/$repo/labels" --jq '.[].name' | tr '\n' ',' 2>/dev/null || echo "")

    for label in $desired_labels; do
        # Skip empty labels that might result from cleaning
        [[ -z "$label" ]] && continue

        if [[ ",${existing_labels}," == *",${label},"* ]]; then
            log_skip "Release label '$label' already exists"
            continue
        fi

        if [[ ",${current_repo_labels}," != *",${label},"* ]]; then
            log_info "Creating release label '$label'"
            gh label create "$label" --color "$LABEL_COLOR" --description "Release automation" \
                || log_warn "Failed to create label '$label' (may already exist)"
        fi

        log_info "Adding release label '$label'"
        if ! gh pr edit "$pr_num" --add-label "$label" >/dev/null; then
            log_warn "Failed to add label '$label' (may already be applied)"
        else
            log_success "Added release label '$label'"
        fi
    done
}

process_milestone() {
    local pr_num=$1
    local desired_milestone=$2

    validate_required "$desired_milestone" "milestone"

    local current_milestone
    current_milestone=$(gh pr view "$pr_num" --json milestone -q '.milestone.title // empty' 2>/dev/null || echo "")

    if [[ "$current_milestone" == "$desired_milestone" ]]; then
        log_skip "Release milestone '$desired_milestone' already set"
    else
        log_info "Setting release milestone '$desired_milestone'"
        if gh pr edit "$pr_num" --milestone "$desired_milestone"; then
            log_success "Release milestone set to '$desired_milestone'"
        else
            log_error "Failed to set release milestone '$desired_milestone'"
        fi
    fi
}

process_assignees() {
    local pr_num=$1
    local desired_assignees=$2
    local existing_assignees=$3

    if [[ -z "$desired_assignees" ]]; then
        log_skip "No release assignees specified"
        return
    fi

    log_info "Processing release assignees..."
    for assignee in $desired_assignees; do
        if [[ ",${existing_assignees}," == *",${assignee},"* ]]; then
            log_skip "Release assignee '$assignee' already assigned"
        else
            log_info "Assigning '$assignee' to release"
            if gh pr edit "$pr_num" --add-assignee "$assignee"; then
                log_success "Assigned '$assignee' to release"
            else
                log_warn "Failed to assign '$assignee' (may not have permissions)"
            fi
        fi
    done
}

process_reviewers() {
    local pr_num=$1
    local desired_reviewers=$2
    local existing_reviewers=$3

    if [[ -z "$desired_reviewers" ]]; then
        log_skip "No release reviewers specified"
        return
    fi

    log_info "Processing release reviewers..."
    for reviewer in $desired_reviewers; do
        if [[ ",${existing_reviewers}," == *",${reviewer},"* ]]; then
            log_skip "Release reviewer '$reviewer' already requested"
        else
            log_info "Requesting review from '$reviewer' for release"
            if gh pr edit "$pr_num" --add-reviewer "$reviewer"; then
                log_success "Review requested from '$reviewer'"
            else
                log_warn "Failed to request review from '$reviewer' (may not have permissions)"
            fi
        fi
    done
}

validate_metadata_content() {
    local metadata_file="$1"

    # Validate required fields
    for field in "${REQUIRED_FIELDS[@]}"; do
        local value
        case "$field" in
            "title") value="$TITLE" ;;
            "labels") value="$LABELS" ;;
            "milestone") value="$MILESTONE" ;;
            *) value=$(get_yaml_value "$field" "$metadata_file") ;;
        esac
        validate_required "$value" "$field"
    done

    log_success "Release metadata validation passed"
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

    echo -e "\n${WHITE}Release Progress: [${filled_bar}] 100% (${total_checks}/$total_checks checks)${NC}"
}

print_summary() {
    echo -e "\n${WHITE}📊 Release Validation Summary:${NC}"
    printf "  ${ICON_PASS} Passed    ${GREEN}🟢  ⇒ %2d\n" "${CHECKS_COUNT[pass]}"
    printf "  ${ICON_WARN} Warnings  ${ORANGE}🟠  ⇒ %2d\n" "${CHECKS_COUNT[warn]}"
    printf "  ${ICON_FAIL} Failures  ${RED}🔴  ⇒ %2d\n" "${CHECKS_COUNT[fail]}"
    printf "  ${ICON_INFO} Info      ${BLUE}🔵  ⇒ %2d\n" "${CHECKS_COUNT[info]}"
    printf "  ${ICON_SKIP} Skipped   ${WHITE}⚫  ⇒ %2d\n" "${CHECKS_COUNT[skip]}"
}

print_release_banner() {
    echo -e "\n${PURPLE}╔══════════════════════════════════════════════════════════════╗"
    echo -e "║${NC}${PURPLE}          🚀  R E L E A S E   P R O C E S S I N G          ${NC}${PURPLE}║"
    echo -e "╚══════════════════════════════════════════════════════════════╝${NC}"
}

# === Version bump + auto-merge helper ===
# Usage: prepare_and_auto_merge_version_bump "<is_initial_release>" "<release_tag>"
prepare_and_auto_merge_version_bump() {
    local is_initial="$1"
    local release_tag="$2"

    # Determine token to use: prefer GH_PAT, fallback to GITHUB_TOKEN/GH_TOKEN
    local gh_pat="${GH_PAT:-${GITHUB_TOKEN:-${GH_TOKEN:-}}}"

    if [[ -z "$gh_pat" ]]; then
        log_warn "GH_PAT / GITHUB_TOKEN / GH_TOKEN not set — cannot auto-merge version bump PR. Skipping auto-version bump."
        return 0
    fi

    export GH_TOKEN="$gh_pat"

    # Ensure jq exists
    if ! command -v jq >/dev/null 2>&1; then
        log_warn "jq not found; install jq to enable JSON parsing for auto-merge. Skipping auto-version bump."
        return 0
    fi

    # compute NEXT_VERSION for snapshot bump (project-specific: Maven example)
    local NEXT_VER
    if [[ "$is_initial" == "true" ]]; then
        NEXT_VER="0.1.0-SNAPSHOT"
    else
        local latest_tag
        latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
        if [[ -z "$latest_tag" ]]; then
            log_warn "Couldn't detect latest tag; defaulting to 0.1.0-SNAPSHOT"
            NEXT_VER="0.1.0-SNAPSHOT"
        else
            IFS='.' read -r MAJOR MINOR PATCH <<< "${latest_tag#v}"
            NEXT_VER="${MAJOR}.$((MINOR+1)).0-SNAPSHOT"
        fi
    fi

    log_info "Prepared NEXT_VERSION=${NEXT_VER}"

    # Avoid duplicate PRs
    local pr_exists
    pr_exists=$(gh pr list --state open --search "Version bump to $NEXT_VER" --json number --jq 'length' 2>/dev/null || echo "0")
    if [[ "$pr_exists" -gt 0 ]]; then
        log_warn "Version bump PR for $NEXT_VER already exists"
        return 0
    fi

    # Create branch from main and push (ensuring up-to-date)
    if ! git fetch origin main:main >/dev/null 2>&1; then
        log_warn "Failed to fetch main; continuing with local main"
    fi

    if ! git checkout main >/dev/null 2>&1; then
        log_error "Failed to checkout main for version bump"
    fi

    if ! git pull origin main >/dev/null 2>&1; then
        log_warn "git pull origin main failed (continuing)"
    fi

    local bump_branch="version-bump/${NEXT_VER}"
    if ! git checkout -b "$bump_branch" >/dev/null 2>&1; then
        log_error "Failed to create branch $bump_branch"
    fi

    # Project-specific version update: default uses Maven. Replace as needed.
    if command -v mvn >/dev/null 2>&1; then
        log_info "Running Maven versions:set -DnewVersion=$NEXT_VER"
        if ! mvn versions:set -DnewVersion="$NEXT_VER" -DgenerateBackupPoms=false >/dev/null 2>&1; then
            log_warn "Maven versions:set failed or made no changes (ensure pom.xml exists and is valid)."
        fi
    else
        log_warn "mvn not found — skipping automatic version update. Please update version manually on branch $bump_branch."
    fi

    # Commit changes (no-op safe)
    git add -A
    if git diff --staged --quiet; then
        log_info "No changes staged for commit (version may already be set)."
    else
        if ! git commit -m "chore: bump version to $NEXT_VER [skip ci]" >/dev/null 2>&1; then
            log_warn "git commit failed or no commit created"
        fi
    fi

    if ! git push -u origin "$bump_branch" >/dev/null 2>&1; then
        log_warn "git push failed for $bump_branch; ensure permissions and network access"
    fi

    # Create PR
    log_info "Creating version-bump PR for $NEXT_VER"
    local pr_json
    if ! pr_json=$(gh pr create \
        --title "Version bump to $NEXT_VER" \
        --body "Automated version bump after release ${release_tag}" \
        --base main \
        --head "$bump_branch" \
        --label "automated,version-bump" \
        --json number,url 2>/dev/null); then
        log_warn "Failed to create version bump PR (gh pr create returned non-zero)."
        return 0
    fi

    local pr_number pr_url
    pr_number=$(jq -r '.number' <<< "$pr_json")
    pr_url=$(jq -r '.url' <<< "$pr_json")
    log_success "Created version bump PR #$pr_number ($pr_url)"

    # Attempt to auto-merge with retries (merge -> squash -> rebase)
    local merged=false
    local attempts=0
    local max_attempts=6

    while [[ $attempts -lt $max_attempts ]]; do
        local mergeable
        mergeable=$(gh pr view "$pr_number" --json mergeable --jq '.mergeable' 2>/dev/null || echo "UNKNOWN")
        log_info "PR mergeable state: $mergeable (attempt $((attempts+1))/$max_attempts)"

        # Try merge strategies
        if gh pr merge "$pr_number" --merge --delete-branch --body "Auto-merged version bump" >/dev/null 2>&1; then
            log_success "Version bump PR #$pr_number merged using --merge"
            merged=true
            break
        fi
        if gh pr merge "$pr_number" --squash --delete-branch --body "Auto-merged version bump (squash)" >/dev/null 2>&1; then
            log_success "Version bump PR #$pr_number merged using --squash"
            merged=true
            break
        fi
        if gh pr merge "$pr_number" --rebase --delete-branch --body "Auto-merged version bump (rebase)" >/dev/null 2>&1; then
            log_success "Version bump PR #$pr_number merged using --rebase"
            merged=true
            break
        fi

        log_warn "Auto-merge attempt $((attempts+1)) failed for PR #$pr_number. Checking for required checks / protections."
        # If branch protection requires checks, wait a bit for checks to complete
        sleep 5
        attempts=$((attempts+1))
    done

    if [[ "$merged" = false ]]; then
        log_warn "Version bump PR #$pr_number was not auto-merged. It remains open at: $pr_url"
        return 0
    fi

    log_success "Version bump PR #$pr_number auto-merged successfully."
    return 0
}

# === Main Execution ===
main() {
    local start_time=$(date +%s)
    print_release_banner

    # Parse CLI args (simple)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --auto-version-bump) AUTO_VERSION_BUMP=true; shift ;;
        --no-auto-bump) AUTO_VERSION_BUMP=false; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) shift ;;
      esac
    done

    log_info "Auto-version-bump: ${AUTO_VERSION_BUMP}"
    log_info "Dry-run: ${DRY_RUN}"

    validate_required_tools

    local current_branch=$(get_current_branch)
    local branch_key="${current_branch#release/}"
    local metadata_file="${METADATA_DIR}/${branch_key}.md"
    [[ -f "$metadata_file" ]] || metadata_file="${METADATA_DIR}/release.md"
    local repo=$(get_repo_name)

    log_info "Release branch: ${current_branch}"
    log_info "Target branch: ${TARGET_BRANCH}"

    # Validate metadata file exists
    [[ -f "$metadata_file" ]] || log_error "Release metadata file not found: $metadata_file"
    log_success "Found release metadata file: $metadata_file"

    # Parse metadata with strict validation
    TITLE=$(get_yaml_value "title" "$metadata_file")
    LINKED_ISSUE=$(get_yaml_value "linked_issue" "$metadata_file")
    MILESTONE=$(get_yaml_value "milestone" "$metadata_file")
    ASSIGNEES=$(clean_array_input "$(get_yaml_value "assignees" "$metadata_file")")
    REVIEWERS=$(clean_array_input "$(get_yaml_value "reviewers" "$metadata_file")")
    LABELS=$(clean_array_input "$(get_yaml_value "labels" "$metadata_file")")

    # Validate metadata content
    validate_metadata_content "$metadata_file"

    log_info "Parsed release metadata:"
    log_info "Title: $TITLE"
    log_info "Milestone: $MILESTONE"
    log_info "Linked Issue: ${LINKED_ISSUE:-none}"
    log_info "Assignees: ${ASSIGNEES:-none}"
    log_info "Reviewers: ${REVIEWERS:-none}"
    log_info "Labels: $LABELS"

    # Get version information
    get_current_version
    get_next_version
    validate_version_increment "$CURRENT_VERSION" "$NEXT_VERSION"

    # Determine release_tag and next_dev (explicit)
    local release_tag dev_next
    if $IS_INITIAL_RELEASE; then
        # For initial release, release_tag is CURRENT_VERSION (v0.0.0)
        release_tag="$CURRENT_VERSION"
        dev_next="$NEXT_VERSION"
    else
        # For normal flow, NEXT_VERSION is the release tag (computed earlier)
        release_tag="$NEXT_VERSION"
        # compute next development version (bump minor)
        local v="${release_tag#v}"; IFS='.' read -r rmaj rmin rpatch <<< "$v"
        dev_next="v${rmaj}.$((rmin+1)).0"
    fi

    # Check for existing PR with robust error handling
    local pr_data
    pr_data=$(get_pr_data "$current_branch")
    PR_NUMBER=$(jq -r '.[0].number // empty' <<< "$pr_data" 2>/dev/null || echo "")
    local pr_state
    pr_state=$(jq -r '.[0].state // empty' <<< "$pr_data" 2>/dev/null || echo "")
    PR_URL=$(jq -r '.[0].url // empty' <<< "$pr_data" 2>/dev/null || echo "")
    local existing_labels
    existing_labels=$(jq -r '[.[0].labels[].name] | join(",") // empty' <<< "$pr_data" 2>/dev/null || echo "")
    local existing_assignees
    existing_assignees=$(jq -r '[.[0].assignees[].login] | join(",") // empty' <<< "$pr_data" 2>/dev/null || echo "")
    local existing_reviewers
    existing_reviewers=$(jq -r '[.[0].reviewRequests[].login] | join(",") // empty' <<< "$pr_data" 2>/dev/null || echo "")

    if [[ -n "$PR_NUMBER" ]]; then
        log_success "Found existing Release PR #$PR_NUMBER ($pr_state)"
        [[ "$pr_state" == "closed" ]] && gh pr reopen "$PR_NUMBER" && log_success "Reopened Release PR #$PR_NUMBER"
    else
        log_info "No existing Release PR found"
    fi

    # Skip CI checks for initial release if no workflows exist
    if $IS_INITIAL_RELEASE && [[ $(check_workflows_exist "$repo") -eq 0 ]]; then
        log_warn "Skipping CI checks for initial release (no workflows detected)"
    else
        wait_for_ci_completion "$repo" "$current_branch"
    fi

    # Generate PR content using explicit release_tag and dev_next
    local release_metadata
    release_metadata=$(generate_release_metadata "$MILESTONE" "$TITLE" "$current_branch" "$LINKED_ISSUE" "$release_tag" "$dev_next")
    local release_notes
    release_notes=$(generate_release_notes "$release_tag" "$dev_next")

    local body_content
    body_content=$(awk '/^---$/{f++; next} f==2' "$metadata_file" || echo "")

    # ------------------------------
    # Robust placeholder replacement
    # ------------------------------
    # Use bash parameter expansion to safely inject multiline metadata; handle common spacing variants.
    local full_body
    full_body="$body_content"
    local repl="$release_metadata"

    # RELEASE_METADATA variants
    full_body="${full_body//\{\{RELEASE_METADATA\}\}/$repl}"
    full_body="${full_body//\{\{ RELEASE_METADATA \}\}/$repl}"
    full_body="${full_body//\{\{RELEASE_METADATA \}\}/$repl}"
    full_body="${full_body//\{\{ RELEASE_METADATA\}\}/$repl}"

    # DYNAMIC_METADATA variants
    full_body="${full_body//\{\{DYNAMIC_METADATA\}\}/$repl}"
    full_body="${full_body//\{\{ DYNAMIC_METADATA \}\}/$repl}"
    full_body="${full_body//\{\{DYNAMIC_METADATA \}\}/$repl}"
    full_body="${full_body//\{\{ DYNAMIC_METADATA\}\}/$repl}"

    # Append release notes
    full_body="${full_body}${release_notes}"

    # If dry-run, just print prepared body and exit
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN - PR title: [RELEASE] $TITLE ($release_tag)"
        echo "DRY RUN - PR body:"
        echo "--------------------"
        echo "$full_body"
        echo "--------------------"
        return 0
    fi

    # Determine PR title: show the actual release tag (Option 2)
    local pr_release_tag="$release_tag"
    local pr_title="[RELEASE] $TITLE (${pr_release_tag})"

    # Create or update PR
    if [[ -z "$PR_NUMBER" ]]; then
        log_info "Creating new Release PR..."
        PR_URL=$(gh pr create \
            --title "$pr_title" \
            --body "$full_body" \
            --base "$TARGET_BRANCH" \
            --head "$current_branch")
        PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$' || echo "")
        log_success "Created Release PR: $PR_URL"
    else
        log_info "Updating Release PR #$PR_NUMBER..."
        gh pr edit "$PR_NUMBER" --title "$pr_title" --body "$full_body"
        log_success "Updated Release PR: $PR_URL"
    fi

    # Process PR metadata with robust error handling
    process_labels "$PR_NUMBER" "$repo" "$LABELS" "$existing_labels"
    process_milestone "$PR_NUMBER" "$MILESTONE"
    process_assignees "$PR_NUMBER" "$ASSIGNEES" "$existing_assignees"
    process_reviewers "$PR_NUMBER" "$REVIEWERS" "$existing_reviewers"

    # Link to issue if specified
    if [[ -n "$LINKED_ISSUE" ]]; then
        log_info "Linking release to issue #$LINKED_ISSUE"
        gh issue comment "$LINKED_ISSUE" --body "Release PR created: $PR_URL" >/dev/null \
            && log_success "Linked to issue #$LINKED_ISSUE" \
            || log_warn "Failed to link to issue #$LINKED_ISSUE"
    fi

    # Final output
    print_progress_bar
    print_summary

    local end_time=$(date +%s)
    echo -e "\n${BLUE}⏱ Release processing completed in $((end_time - start_time)) seconds${NC}"

    if [[ ${CHECKS_COUNT[fail]} -gt 0 ]]; then
        log_error "❌ Release processing completed with errors"
    else
        echo -e "\n${PURPLE}╔══════════════════════════════════════════════════════════════╗"
        echo -e "║${NC}${GREEN}          🎉  R E L E A S E   R E A D Y           ${NC}${PURPLE}║"
        echo -e "╚══════════════════════════════════════════════════════════════╝${NC}"
        log_success "${ICON_RELEASE} Release PR successfully processed: ${BLUE}${PR_URL}${NC}"

        # Fixed version message (show actual release tag)
        echo -e "${ICON_VERSION} ${BLUE}Release tag to be created: ${GREEN}${release_tag}${BLUE}${NC}"
        echo -e "${ICON_VERSION} ${BLUE}Next development version: ${GREEN}${dev_next}${BLUE}${NC}"
    fi

    # Auto version bump if requested
    if [[ "$AUTO_VERSION_BUMP" == "true" ]]; then
        log_info "AUTO_VERSION_BUMP enabled — attempting to create + auto-merge version bump PR"
        prepare_and_auto_merge_version_bump "$IS_INITIAL_RELEASE" "${pr_release_tag}"
    fi
}

# Entry point
main "$@"
# release-pr.sh
