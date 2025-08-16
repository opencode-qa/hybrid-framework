#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# GitHub Milestone Manager - Enhanced Output & Emoji Marking
# Usage:
#   ./scripts/milestones.sh -o <owner> -r <repo> -m <milestones.json> [-s spacing_days] [-t default_due_time] [--dry-run]
# Example:
#   ./scripts/milestones.sh -o opencode-qa -r hybrid-framework -m milestones.json
# =============================================================================

# -------------------------
# Defaults (can be overridden via CLI)
# -------------------------
OWNER=""
REPO=""
MILESTONE_FILE=""
START_DATE=$(date -d "next Monday" +%Y-%m-%d)  # default next Monday
SPACING_DAYS=7
DEFAULT_DUE_TIME="23:59:59"
DRY_RUN=false

# -------------------------
# CLI parsing
# -------------------------
usage() {
  cat <<EOF
Usage: $0 -o OWNER -r REPO -m MILESTONE_FILE [-s SPACING_DAYS] [-t DEFAULT_DUE_TIME] [--dry-run]
  -o OWNER             GitHub owner or organization (required)
  -r REPO              GitHub repository (required)
  -m MILESTONE_FILE    JSON file with milestone definitions (required)
  -s SPACING_DAYS      Days between milestones (default: ${SPACING_DAYS})
  -t DEFAULT_DUE_TIME  Default due time (default: ${DEFAULT_DUE_TIME})
  --dry-run            Do not call GitHub API, only print actions
EOF
  exit 1
}

# parse args
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) OWNER="$2"; shift 2 ;;
    -r) REPO="$2"; shift 2 ;;
    -m) MILESTONE_FILE="$2"; shift 2 ;;
    -s) SPACING_DAYS="$2"; shift 2 ;;
    -t) DEFAULT_DUE_TIME="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

if [ -z "$OWNER" ] || [ -z "$REPO" ] || [ -z "$MILESTONE_FILE" ]; then
  usage
fi

# -------------------------
# Colors & Styles
# -------------------------
# Attempt to initialize tput; if not available, fallback to empty strings
if command -v tput >/dev/null 2>&1; then
  BOLD=$(tput bold)
  RESET=$(tput sgr0)
  UNDERLINE=$(tput smul)
  COLOR_HEADER=$(tput setaf 33)      # Blue-ish
  COLOR_PHASE1=$(tput setaf 39)      # Cyan
  COLOR_PHASE2=$(tput setaf 208)     # Orange
  COLOR_SUMMARY=$(tput setaf 200)    # Pink
  COLOR_TIMESTAMP=$(tput setaf 99)   # Purple

  COLOR_CREATED=$(tput setaf 46)     # Green
  COLOR_SKIPPED=$(tput setaf 244)    # Gray
  COLOR_FAILED=$(tput setaf 196)     # Red
  COLOR_OPEN=$(tput setaf 255)       # White
  COLOR_CLOSED=$(tput setaf 46)      # Green
  COLOR_REOPENED=$(tput setaf 39)    # Blue
  COLOR_UPCOMING=$(tput setaf 214)   # Orange
  COLOR_ONTRACK=$(tput setaf 255)    # White
  COLOR_OVERDUE=$(tput setaf 201)    # Purple
else
  BOLD=""; RESET=""; UNDERLINE=""
  COLOR_HEADER=""; COLOR_PHASE1=""; COLOR_PHASE2=""; COLOR_SUMMARY=""; COLOR_TIMESTAMP=""
  COLOR_CREATED=""; COLOR_SKIPPED=""; COLOR_FAILED=""; COLOR_OPEN=""; COLOR_CLOSED=""; COLOR_REOPENED=""
  COLOR_UPCOMING=""; COLOR_ONTRACK=""; COLOR_OVERDUE=""
fi

# Icons / Symbols
ICON_CREATED="✓"
ICON_SKIPPED="↻"
ICON_FAILED="✗"
ICON_OPEN="◌"
ICON_CLOSED="☑"
ICON_REOPENED="⟳"
ICON_UPCOMING="▶"
ICON_ONTRACK="➣"
ICON_OVERDUE="?"

SYM_CREATED="🟢"
SYM_SKIPPED="⚫"
SYM_FAILED="🔴"
SYM_OPEN="⚪"
SYM_CLOSED="🟢"
SYM_REOPENED="🔵"
SYM_UPCOMING="🟠"
SYM_ONTRACK="⚪"
SYM_OVERDUE="🟣"

BLOCK_CREATED="🟩"
BLOCK_SKIPPED="⬛"
BLOCK_FAILED="🟥"
BLOCK_OPEN="⬜"
BLOCK_CLOSED="🟩"
BLOCK_REOPENED="🟦"
BLOCK_UPCOMING="🟧"
BLOCK_ONTRACK="⬜"
BLOCK_OVERDUE="🟪"

DIVIDER="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SUBDIVIDER="────────────────────────────────────────────────────────────────"

# -------------------------
# Helpers
# -------------------------
timestamp_now() {
  date '+%d-%b-%Y %H:%M:%S'
}

timestamp_short() {
  # For due date display like "15 Aug 2025"
  date -d "$1" +"%d %b %Y"
}

colorize_number() {
  local number="$1" color="$2"
  printf "%b%s%b" "${BOLD}${color}" "$number" "${RESET}"
}

# print header
print_header() {
  echo
  echo -e "${COLOR_HEADER}${BOLD}╔══════════════════════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${COLOR_HEADER}${BOLD}║                      GitHub Milestone Manager - Enhanced Edition                 ║${RESET}"
  echo -e "${COLOR_HEADER}${BOLD}╚══════════════════════════════════════════════════════════════════════════════════╝${RESET}"
  echo
}

# print section / subsection
print_section() {
  local title="$1" color="$2"
  echo
  echo -e "${color}${BOLD}${DIVIDER}${RESET}"
  echo -e "${color}${BOLD}❯ ${title}${RESET}"
  echo -e "${color}${BOLD}${DIVIDER}${RESET}"
}

print_subsection() {
  local title="$1" color="$2"
  echo
  echo -e "${color}${BOLD}${SUBDIVIDER}${RESET}"
  echo -e "${color}${BOLD}${title}${RESET}"
  echo -e "${color}${BOLD}${SUBDIVIDER}${RESET}"
}

# print status with optional timestamp (if timestamp_str provided, show it; else show current)
print_status() {
  local icon="$1" color="$2" message="$3" timestamp_str="$4"
  local ts_display
  if [ -n "$timestamp_str" ]; then
    ts_display="$timestamp_str"
  else
    ts_display="$(timestamp_now)"
  fi
  # Example desired format (all bold): ↻ v0.0.0 → ⚫ ⇒ Existing  [15-Aug-2025 00:17:58]
  printf "%b${BOLD}%s %s%b  [%s]%b\n" "$color" "$icon" "$message" "$RESET" "$ts_display" "$RESET"
}

# Progress bar that maps status letters to colored blocks
print_progress_bar() {
  local -n statuses=$1
  printf "["
  for s in "${statuses[@]}"; do
    case "$s" in
      C) printf "%b%s%b" "${COLOR_CREATED}" "${BLOCK_CREATED}" "${RESET}" ;;
      S) printf "%b%s%b" "${COLOR_SKIPPED}" "${BLOCK_SKIPPED}" "${RESET}" ;;
      F) printf "%b%s%b" "${COLOR_FAILED}" "${BLOCK_FAILED}" "${RESET}" ;;
      O) printf "%b%s%b" "${COLOR_OPEN}" "${BLOCK_OPEN}" "${RESET}" ;;
      D) printf "%b%s%b" "${COLOR_CLOSED}" "${BLOCK_CLOSED}" "${RESET}" ;;
      R) printf "%b%s%b" "${COLOR_REOPENED}" "${BLOCK_REOPENED}" "${RESET}" ;;
      P) printf "%b%s%b" "${COLOR_UPCOMING}" "${BLOCK_UPCOMING}" "${RESET}" ;;
      T) printf "%b%s%b" "${COLOR_ONTRACK}" "${BLOCK_ONTRACK}" "${RESET}" ;;
      V) printf "%b%s%b" "${COLOR_OVERDUE}" "${BLOCK_OVERDUE}" "${RESET}" ;;
      *) printf " " ;;
    esac
  done
  printf "] 100%% [%d/%d]\n" "${#statuses[@]}" "${#statuses[@]}"
}

# Summaries
print_creation_summary() {
  local created="$1" skipped="$2" failed="$3" color="$4"
  echo
  echo -e "${color}${BOLD}${SUBDIVIDER}${RESET}"
  echo -e "${color}${BOLD}📝 Creation Summary${RESET}"
  echo -e "${color}${BOLD}${SUBDIVIDER}${RESET}"
  printf "%b${BOLD}${ICON_CREATED} Created ${SYM_CREATED} ⇒ %s%b  |  %b${BOLD}${ICON_SKIPPED} Skipped ${SYM_SKIPPED} ⇒ %s%b  |  %b${BOLD}${ICON_FAILED} Failure ${SYM_FAILED} ⇒ %s%b\n" \
    "${COLOR_CREATED}" "$(colorize_number "$created" "$COLOR_CREATED")" "${RESET}" \
    "${COLOR_SKIPPED}" "$(colorize_number "$skipped" "$COLOR_SKIPPED")" "${RESET}" \
    "${COLOR_FAILED}" "$(colorize_number "$failed" "$COLOR_FAILED")" "${RESET}"
}

print_sync_summary() {
  local created="$1" skipped="$2" failed="$3" open="$4" closed="$5" reopened="$6" color="$7"
  echo
  echo -e "${color}${BOLD}${SUBDIVIDER}${RESET}"
  echo -e "${color}${BOLD}⚙ Synchronization Results${RESET}"
  echo -e "${color}${BOLD}${SUBDIVIDER}${RESET}"
  printf "%b${BOLD}${ICON_CREATED} Created ${SYM_CREATED} ⇒ %s%b  |  %b${BOLD}${ICON_SKIPPED} Skipped ${SYM_SKIPPED} ⇒ %s%b  |  %b${BOLD}${ICON_FAILED} Failure ${SYM_FAILED} ⇒ %s%b\n" \
    "${COLOR_CREATED}" "$(colorize_number "$created" "$COLOR_CREATED")" "${RESET}" \
    "${COLOR_SKIPPED}" "$(colorize_number "$skipped" "$COLOR_SKIPPED")" "${RESET}" \
    "${COLOR_FAILED}" "$(colorize_number "$failed" "$COLOR_FAILED")" "${RESET}"

  printf "%b${BOLD}${ICON_OPEN} Open ${SYM_OPEN} ⇒ %s%b  |  %b${BOLD}${ICON_CLOSED} Closed ${SYM_CLOSED} ⇒ %s%b  |  %b${BOLD}${ICON_REOPENED} Reopened ${SYM_REOPENED} ⇒ %s%b\n" \
    "${COLOR_OPEN}" "$(colorize_number "$open" "$COLOR_OPEN")" "${RESET}" \
    "${COLOR_CLOSED}" "$(colorize_number "$closed" "$COLOR_CLOSED")" "${RESET}" \
    "${COLOR_REOPENED}" "$(colorize_number "$reopened" "$COLOR_REOPENED")" "${RESET}"
}

print_health_summary() {
  local upcoming="$1" on_track="$2" overdue="$3" closed="$4" reopened="$5" color="$6"
  echo
  echo -e "${color}${BOLD}${SUBDIVIDER}${RESET}"
  echo -e "${color}${BOLD}🔮 Health Overview${RESET}"
  echo -e "${color}${BOLD}${SUBDIVIDER}${RESET}"
  printf "%b${BOLD}${ICON_UPCOMING} Upcoming ${SYM_UPCOMING} ⇒ %s%b  |  %b${BOLD}${ICON_ONTRACK} On Track ${SYM_ONTRACK} ⇒ %s%b  |  %b${BOLD}${ICON_OVERDUE} Overdue ${SYM_OVERDUE} ⇒ %s%b\n" \
    "${COLOR_UPCOMING}" "$(colorize_number "$upcoming" "$COLOR_UPCOMING")" "${RESET}" \
    "${COLOR_ONTRACK}" "$(colorize_number "$on_track" "$COLOR_ONTRACK")" "${RESET}" \
    "${COLOR_OVERDUE}" "$(colorize_number "$overdue" "$COLOR_OVERDUE")" "${RESET}"

  printf "%b${BOLD}${ICON_CLOSED} Closed ${SYM_CLOSED} ⇒ %s%b  |  %b${BOLD}${ICON_REOPENED} Reopened ${SYM_REOPENED} ⇒ %s%b\n" \
    "${COLOR_CLOSED}" "$(colorize_number "$closed" "$COLOR_CLOSED")" "${RESET}" \
    "${COLOR_REOPENED}" "$(colorize_number "$reopened" "$COLOR_REOPENED")" "${RESET}"
}

# -------------------------
# GitHub API wrapper
# -------------------------
gh_api() {
  if [ "$DRY_RUN" = true ]; then
    # Print what would be executed and return mock empty JSON where appropriate
    echo "[DRY RUN] gh api $*"
    return 0
  fi

  output=$(gh api "$@" 2>&1) || {
    status=$?
    # Error handling for common errors
    if [[ $output == *"HTTP 404"* ]]; then
      echo -e "${COLOR_FAILED}${BOLD}Error: Repository or resource not found. Verify:${RESET}"
      echo -e "  - Organization: ${COLOR_UPCOMING}$OWNER${RESET}"
      echo -e "  - Repository: ${COLOR_UPCOMING}$REPO${RESET}"
      echo -e "${COLOR_FAILED}Ensure the repository exists and you have access rights.${RESET}"
      exit 1
    elif [[ $output == *"HTTP 401"* ]] || [[ $output == *"HTTP 403"* ]]; then
      echo -e "${COLOR_FAILED}${BOLD}Authentication/Authorization error. Please check GitHub CLI authentication.${RESET}"
      echo -e "Run: ${COLOR_PHASE1}gh auth login${RESET}"
      exit 1
    else
      echo -e "${COLOR_FAILED}${BOLD}GitHub API error (exit $status):${RESET}"
      echo "$output"
      exit $status
    fi
  }

  echo "$output"
}

# -------------------------
# GitHub milestone helpers
# -------------------------
fetch_existing_milestones() {
  # returns newline separated JSON objects
  gh_api "repos/$OWNER/$REPO/milestones?state=all" --paginate
}

create_github_milestone() {
  local title="$1" description="$2" due_on="$3" state="$4"

  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] create milestone: title='$title' state='$state' due_on='$due_on'"
    return 0
  fi

  args=( "repos/$OWNER/$REPO/milestones" -X POST )
  [ -n "$title" ] && args+=( -f "title=$title" )
  [ -n "$description" ] && args+=( -f "description=$description" )
  [ -n "$due_on" ] && args+=( -f "due_on=$due_on" )
  [ -n "$state" ] && args+=( -f "state=$state" )

  gh_api "${args[@]}"
}

update_github_milestone() {
  local number="$1" title="$2" description="$3" due_on="$4" state="$5"

  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] update milestone: #$number title='$title' state='$state' due_on='$due_on'"
    return 0
  fi

  args=( "repos/$OWNER/$REPO/milestones/$number" -X PATCH )
  [ -n "$title" ] && args+=( -f "title=$title" )
  [ -n "$description" ] && args+=( -f "description=$description" )
  [ -n "$due_on" ] && args+=( -f "due_on=$due_on" )
  [ -n "$state" ] && args+=( -f "state=$state" )

  gh_api "${args[@]}"
}

get_milestone_issues() {
  local milestone_number="$1"
  # state=all to count both open and closed
  gh_api "repos/$OWNER/$REPO/issues?milestone=$milestone_number&state=all" --paginate
}

# Adds emoji to the beginning of the milestone description on GitHub, avoids duplicates
add_emoji_to_description() {
  local milestone_number="$1" status="$2"
  local emoji=""
  case "$status" in
    "Upcoming") emoji="🟠" ;;
    "Closed")   emoji="🟢" ;;
    "Overdue")  emoji="🟣" ;;
    *) return 0 ;;
  esac

  local current_desc
  current_desc=$(gh_api "repos/$OWNER/$REPO/milestones/$milestone_number" | jq -r '.description // ""')

  # If description already begins with the emoji, skip
  if [[ "$current_desc" == "$emoji"* ]]; then
    return 0
  fi

  # prepend emoji
  local new_desc="$emoji $current_desc"
  update_github_milestone "$milestone_number" "" "$new_desc" "" ""
}

# -------------------------
# Core logic
# -------------------------
process_milestones() {
  local created_count=0 skipped_count=0 failed_count=0
  local open_count=0 closed_count=0 reopened_count=0
  local upcoming_count=0 on_track_count=0 overdue_count=0
  local total_issues=0 open_issues_total=0

  declare -a creation_statuses=() state_statuses=() health_statuses=()
  declare -a existing_list=()

  # Load milestone file
  if [ ! -f "$MILESTONE_FILE" ]; then
    echo -e "${COLOR_FAILED}${BOLD}Error: Milestones file not found: $MILESTONE_FILE${RESET}"
    exit 1
  fi

  total_milestones=$(jq 'length' "$MILESTONE_FILE" 2>/dev/null || echo "0")
  if [ "$total_milestones" = "0" ]; then
    echo -e "${COLOR_FAILED}${BOLD}Error: Milestones file is empty or invalid JSON: $MILESTONE_FILE${RESET}"
    exit 1
  fi

  # Fetch existing milestones from GitHub (raw JSON array). We will transform it to one-object-per-line.
  existing_raw=$(fetch_existing_milestones)
  # Transform to one JSON object per line for safe iteration
  existing_milestones=$(echo "$existing_raw" | jq -c '.[]' 2>/dev/null || echo "")

  # -------------------------
  # PHASE 1: Synchronization - Create milestones if not exist
  # -------------------------
  print_section "PHASE 1: MILESTONE SYNCHRONIZATION" "$COLOR_PHASE1"
  echo -e "${COLOR_PHASE1}${BOLD}🗘 Processing milestones...${RESET}"

  print_subsection "❯ CREATE MILESTONES" "$COLOR_PHASE1"

  # read each milestone from file
  while IFS= read -r milestone; do
    title=$(jq -r '.title' <<< "$milestone")
    description=$(jq -r '.description // ""' <<< "$milestone")
    due_on=$(jq -r '.due_on // empty' <<< "$milestone")
    state=$(jq -r '.state // "open"' <<< "$milestone")

    # check existence by title in existing_milestones
    if [ -z "$existing_milestones" ]; then
      existing=""
    else
      existing=$(jq -c --arg t "$title" 'select(.title == $t)' <<< "$existing_milestones" || true)
    fi

    if [ -z "$existing" ]; then
      # create
      if output=$(create_github_milestone "$title" "$description" "$due_on" "$state" 2>&1); then
        print_status "$ICON_CREATED" "$COLOR_CREATED" "$title ⇒ Created" "$(timestamp_now)"
        creation_statuses+=("C")
        created_count=$((created_count+1))
      else
        print_status "$ICON_FAILED" "$COLOR_FAILED" "$title ⇒ Failed: ${output:0:80}" "$(timestamp_now)"
        creation_statuses+=("F")
        failed_count=$((failed_count+1))
      fi
    else
      # skip
      print_status "$ICON_SKIPPED" "$COLOR_SKIPPED" "$title → $SYM_SKIPPED ⇒ Existing" "$(timestamp_now)"
      creation_statuses+=("S")
      skipped_count=$((skipped_count+1))
    fi
  done < <(jq -c '.[]' "$MILESTONE_FILE")

  # print creation progress & summary (bold & colored)
  print_progress_bar creation_statuses
  print_creation_summary "$created_count" "$skipped_count" "$failed_count" "$COLOR_PHASE1"

  # -------------------------
  # PHASE 1b: Update metadata & Reopening / state counts
  # -------------------------
  echo -e "\n${COLOR_PHASE1}${BOLD}🌀 Fetching milestones from GitHub...${RESET} $(timestamp_now)"
  print_subsection "❯ UPDATE METADATA & REOPENING" "$COLOR_PHASE1"

  open_count=0
  closed_count=0
  # Build existing_milestones array (one JSON per line)
  mapfile -t existing_list < <(echo "$existing_milestones" | sed '/^\s*$/d' || true)

  for m in "${existing_list[@]}"; do
    title=$(jq -r '.title' <<< "$m")
    state=$(jq -r '.state' <<< "$m")
    number=$(jq -r '.number' <<< "$m")
    ts="$(timestamp_now)"

    if [ "$state" = "open" ]; then
      print_status "$ICON_OPEN" "$COLOR_OPEN" "$title → $SYM_OPEN ⇒ Open" "$ts"
      state_statuses+=("O")
      open_count=$((open_count+1))
    else
      print_status "$ICON_CLOSED" "$COLOR_CLOSED" "$title → $SYM_CLOSED ⇒ Closed" "$ts"
      state_statuses+=("D")
      closed_count=$((closed_count+1))
    fi
  done

  print_progress_bar state_statuses
  print_sync_summary "$created_count" "$skipped_count" "$failed_count" "$open_count" "$closed_count" "$reopened_count" "$COLOR_PHASE1"

  # -------------------------
  # PHASE 2: Health Management - determine upcoming (nearest due date), on track, overdue.
  # -------------------------
  print_section "PHASE 2: MILESTONE HEALTH MANAGEMENT" "$COLOR_PHASE2"
  echo -e "${COLOR_PHASE2}${BOLD}🌟 Refreshing milestone data from GitHub...${RESET} $(timestamp_now)"

  print_subsection "❯ Milestone Status Review" "$COLOR_PHASE2"

  # We'll compute diff_days for each existing milestone and pick the nearest non-negative (future or today)
  declare -a diffs=()   # parallel array for diff_days
  declare -a ms_numbers=()
  declare -a ms_jsons=()

  # populate arrays
  for m in "${existing_list[@]}"; do
    number=$(jq -r '.number' <<< "$m")
    title=$(jq -r '.title' <<< "$m")
    due_on=$(jq -r '.due_on // empty' <<< "$m")
    state=$(jq -r '.state' <<< "$m")

    if [ -n "$due_on" ]; then
      # convert to epoch seconds; some due_on may include timezone; handle gracefully
      due_ts=$(date -d "$due_on" +%s 2>/dev/null || echo 0)
      now_ts=$(date +%s)
      if [ "$due_ts" -gt 0 ]; then
        diff_days=$(( (due_ts - now_ts) / 86400 ))
      else
        diff_days=99999
      fi
    else
      diff_days=99999
    fi

    diffs+=( "$diff_days" )
    ms_numbers+=( "$number" )
    ms_jsons+=( "$m" )
  done

  # determine index of nearest non-negative diff (closest upcoming)
  closest_index=-1
  closest_val=99999
  for i in "${!diffs[@]}"; do
    val=${diffs[$i]}
    if [ "$val" -ge 0 ] && [ "$val" -lt "$closest_val" ]; then
      closest_val=$val
      closest_index=$i
    fi
  done

  # Iterate again to compute issues and health statuses
  for i in "${!ms_jsons[@]}"; do
    m="${ms_jsons[$i]}"
    number=$(jq -r '.number' <<< "$m")
    title=$(jq -r '.title' <<< "$m")
    state=$(jq -r '.state' <<< "$m")
    due_on=$(jq -r '.due_on // empty' <<< "$m")
    diff_days=${diffs[$i]}

    # count issues
    open_issues=0
    closed_issues=0
    issues_raw=$(get_milestone_issues "$number" || true)
    if [ -n "$issues_raw" ]; then
      mapfile -t issues_arr < <(echo "$issues_raw" | jq -c '.[]?' 2>/dev/null || true)
      for issue in "${issues_arr[@]}"; do
        issue_state=$(jq -r '.state' <<< "$issue")
        if [ "$issue_state" = "open" ]; then
          open_issues=$((open_issues+1))
        else
          closed_issues=$((closed_issues+1))
        fi
      done
    fi

    total=$((open_issues + closed_issues))
    total_issues=$((total_issues + total))
    open_issues_total=$((open_issues_total + open_issues))

    # Format due info
    if [ -n "$due_on" ] && [ "$diff_days" -ne 99999 ]; then
      due_date_fmt=$(date -d "$due_on" +"%d %b %Y")
      due_info="→ $due_date_fmt (due in $diff_days days)"
    elif [ -n "$due_on" ]; then
      due_date_fmt=$(date -d "$due_on" +"%d %b %Y" 2>/dev/null || echo "$due_on")
      due_info="→ $due_date_fmt"
    else
      due_info="→ No due date"
    fi

    # Determine health and act (reopen/close) - keep colors and emoji marking
    health_status=""
    icon=""
    color=""
    ts="$(timestamp_now)"

    if [ "$state" = "closed" ] && [ "$open_issues" -gt 0 ]; then
      # Reopen incomplete milestone
      if update_github_milestone "$number" "" "" "" "open" >/dev/null 2>&1 || [ "$DRY_RUN" = true ]; then
        health_status="Reopened"
        icon="$SYM_REOPENED $ICON_REOPENED"
        color="$COLOR_REOPENED"
        health_statuses+=("R")
        reopened_count=$((reopened_count+1))
        # Add blue block for reopened
      fi
    elif [ "$state" = "open" ] && [ "$open_issues" -eq 0 ] && [ "$total" -gt 0 ]; then
      # Close completed milestone
      if update_github_milestone "$number" "" "" "" "closed" >/dev/null 2>&1 || [ "$DRY_RUN" = true ]; then
        health_status="Closed"
        icon="$SYM_CLOSED $ICON_CLOSED"
        color="$COLOR_CLOSED"
        health_statuses+=("D")
        closed_count=$((closed_count+1))
        # Add green block
      fi
    else
      # Status reporting
      if [ -n "$due_on" ] && [ "$diff_days" -ne 99999 ]; then
        if [ "$diff_days" -lt 0 ]; then
          health_status="Overdue"
          icon="$SYM_OVERDUE $ICON_OVERDUE"
          color="$COLOR_OVERDUE"
          health_statuses+=("V")
          overdue_count=$((overdue_count+1))
          # Add purple block
          # Add emoji to description
          add_emoji_to_description "$number" "Overdue" || true
        elif [ "$i" -eq "$closest_index" ]; then
          # This is the single closest upcoming milestone
          health_status="Upcoming"
          icon="$SYM_UPCOMING $ICON_UPCOMING"
          color="$COLOR_UPCOMING"
          health_statuses+=("P")
          upcoming_count=$((upcoming_count+1))
          add_emoji_to_description "$number" "Upcoming" || true
        else
          health_status="On track"
          icon="$SYM_ONTRACK $ICON_ONTRACK"
          color="$COLOR_ONTRACK"
          health_statuses+=("T")
          on_track_count=$((on_track_count+1))
        fi
      else
        health_status="On track"
        icon="$SYM_ONTRACK $ICON_ONTRACK"
        color="$COLOR_ONTRACK"
        health_statuses+=("T")
        on_track_count=$((on_track_count+1))
      fi
    fi

    # Print in desired format:
    # ◌ v0.0.0 → 15 Aug 2025 (due in 0 days) ⇒ 🟠 Upcoming [0 open / 0 closed]  [15-Aug-2025 00:25:48]
    if [ -n "$health_status" ]; then
      status_msg="$title $due_info ⇒ $icon $health_status [$open_issues open / $closed_issues closed]"
      print_status "$ICON_OPEN" "$color" "$status_msg" "$ts"
    fi
  done

  # Print health progress bar & summary
  [ ${#health_statuses[@]} -gt 0 ] && print_progress_bar health_statuses
  print_health_summary "$upcoming_count" "$on_track_count" "$overdue_count" "$closed_count" "$reopened_count" "$COLOR_PHASE2"

  # FINAL SUMMARY
  print_section "FINAL SUMMARY" "$COLOR_SUMMARY"
  echo
  printf "%b%-20s %-12s %-30s%b\n" "${COLOR_SUMMARY}${BOLD}" "Category" "Count" "Notes" "${RESET}"
  printf "%b%-20s %-12s %-30s%b\n" "${COLOR_SUMMARY}" "──────────────────" "──────────" "──────────────────────────────" "${RESET}"
  printf "%-20s %-12s %-30s\n" "Total Milestones" "$(colorize_number "$total_milestones" "$COLOR_SUMMARY")" "All milestones processed"
  printf "%-20s %-12s %-30s\n" "Synchronized" "$(colorize_number "$((created_count + skipped_count))" "$COLOR_PHASE1")" "Descriptions/dates updated"
  printf "%-20s %-12s %-30s\n" "Completed" "$(colorize_number "$closed_count" "$COLOR_CLOSED")" "100% closed milestones"
  printf "%-20s %-12s %-30s\n" "Reopened" "$(colorize_number "$reopened_count" "$COLOR_REOPENED")" "Incomplete milestones reopened"
  printf "%-20s %-12s %-30s\n" "Issues Tracked" "$(colorize_number "$total_issues" "$COLOR_PHASE1")" "Total issues across milestones"
  echo

  if [ "$open_issues_total" -gt 0 ]; then
    echo -e "\n${COLOR_FAILED}${BOLD}❗ Attention: There are $open_issues_total open issues across all milestones${RESET} $(timestamp_now)"
  fi

  echo -e "\n${COLOR_CREATED}${BOLD}🎉 Milestone management completed successfully for ${UNDERLINE}${OWNER}/${REPO}${RESET}"
  echo -e "\n${COLOR_SUMMARY}${BOLD}💫 Thank you for using GitHub Milestone Manager!${RESET}"
  echo -e "\n${COLOR_PHASE1}Completed at: $(timestamp_now)${RESET}\n"
}

# -------------------------
# Main
# -------------------------
main() {
  # Requirements
  if ! command -v gh >/dev/null 2>&1; then
    echo -e "${COLOR_FAILED}${BOLD}Error: GitHub CLI (gh) not installed. Please install and authenticate.${RESET}"
    echo -e "Installation: https://github.com/cli/cli#installation"
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo -e "${COLOR_FAILED}${BOLD}Error: jq is not installed. Please install it.${RESET}"
    echo -e "Installation: https://stedolan.github.io/jq/download/"
    exit 1
  fi
  if [ "$DRY_RUN" = false ]; then
    if ! gh auth status >/dev/null 2>&1; then
      echo -e "${COLOR_FAILED}${BOLD}Error: GitHub CLI not authenticated. Run 'gh auth login'.${RESET}"
      exit 1
    fi
  fi

  clear
  print_header
  echo -e "🎯 ${COLOR_PHASE1}Initializing GitHub Milestone Manager for: ${BOLD}${OWNER}/${REPO}${RESET} $(timestamp_now)"
  echo -e "🔧 ${COLOR_PHASE1}Configuration    ⇒ $(timestamp_now)"
  echo -e "  💡 ${COLOR_OPEN}Start Date     ⇒ ${COLOR_UPCOMING}${START_DATE}${RESET}"
  echo -e "  ⇄ ${COLOR_OPEN}Spacing Days    ⇒ ${COLOR_UPCOMING}${SPACING_DAYS}${RESET}"
  echo -e "  🕛 ${COLOR_OPEN}Default Time   ⇒ ${COLOR_UPCOMING}${DEFAULT_DUE_TIME}${RESET}"
  echo -e "  𓊕 ${COLOR_OPEN}Dry Run         ⇒ ${COLOR_UPCOMING}${DRY_RUN}${RESET}"

  process_milestones
}

main "$@"
