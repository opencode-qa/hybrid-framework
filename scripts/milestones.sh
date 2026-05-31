#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# GitHub Milestone Manager - Ultimate Edition
# Color Philosophy: Created 🟡, Open ⚪, Closed 🟢, Reopened 🔵,
#                   Upcoming 🟠, Overdue 🟣, Failed 🔴, Skipped ⚫
# =============================================================================

# -------------------------
# Defaults
# -------------------------
OWNER=""
REPO=""
MILESTONE_FILE=""
START_DATE=""
SPACING_DAYS=7
DEFAULT_DUE_TIME="23:59:59"
DRY_RUN=false
NO_CLEAR=false

# -------------------------
# CLI parsing
# -------------------------
usage() {
  cat <<EOF
Usage: $0 -o OWNER -r REPO -m MILESTONE_FILE [options]

Required:
  -o OWNER             GitHub owner or organization
  -r REPO              GitHub repository
  -m MILESTONE_FILE    JSON file with milestone definitions

Options:
  --start-date YYYY-MM-DD   First milestone due date (default: next Monday)
  --spacing-days N          Days between milestones (default: 7)
  --default-time HH:MM:SS   Default due time (default: 23:59:59)
  --dry-run                 Do not call GitHub API, only print actions
  --no-clear                Do not clear the screen before running
  -h, --help                Show this help
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) OWNER="$2"; shift 2 ;;
    -r) REPO="$2"; shift 2 ;;
    -m) MILESTONE_FILE="$2"; shift 2 ;;
    --start-date) START_DATE="$2"; shift 2 ;;
    --spacing-days) SPACING_DAYS="$2"; shift 2 ;;
    --default-time) DEFAULT_DUE_TIME="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --no-clear) NO_CLEAR=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

if [ -z "$OWNER" ] || [ -z "$REPO" ] || [ -z "$MILESTONE_FILE" ]; then
  usage
fi

# -------------------------
# Portable date handling
# -------------------------
if command -v date >/dev/null && date -d "next Monday" >/dev/null 2>&1; then
  HAVE_GNU_DATE=true
else
  HAVE_GNU_DATE=false
fi

if [ -z "$START_DATE" ]; then
  if $HAVE_GNU_DATE; then
    START_DATE=$(date -d "next Monday" +%Y-%m-%d)
  else
    START_DATE=$(python3 -c "from datetime import date, timedelta; print((date.today() + timedelta(days=7)).isoformat())" 2>/dev/null || date -v+7d +%Y-%m-%d 2>/dev/null || echo "2026-06-01")
  fi
fi

compute_due_date() {
  local base_date="$1"
  local offset_days="$2"
  local time_part="$3"
  if $HAVE_GNU_DATE; then
    due_iso=$(date -d "$base_date + $offset_days days" +"%Y-%m-%dT$time_part%z" 2>/dev/null || echo "")
  else
    due_iso=$(python3 -c "
from datetime import datetime, timedelta
d = datetime.strptime('$base_date', '%Y-%m-%d') + timedelta(days=$offset_days)
print(d.strftime('%Y-%m-%dT$time_part%z'))
" 2>/dev/null) || due_iso=""
    if [ -z "$due_iso" ] && command -v date >/dev/null; then
      due_iso=$(date -v+"${offset_days}"d -j -f "%Y-%m-%d" "$base_date" +"%Y-%m-%dT$time_part%z" 2>/dev/null || echo "")
    fi
  fi
  if [ -z "$due_iso" ]; then
    due_iso="${base_date}T$time_part+00:00"
  fi
  echo "$due_iso"
}

# -------------------------
# Colors & Styles (New Philosophy)
# -------------------------
if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
  BOLD=$(tput bold)
  RESET=$(tput sgr0)
  UNDERLINE=$(tput smul)
  COLOR_HEADER=$(tput setaf 33)      # blue
  COLOR_PHASE1=$(tput setaf 39)      # cyan
  COLOR_PHASE2=$(tput setaf 208)     # orange
  COLOR_SUMMARY=$(tput setaf 200)    # magenta
  COLOR_TIMESTAMP=$(tput setaf 99)   # purple (timestamps only)
  COLOR_DIVIDER=$(tput setaf 27)     # blue

  # Main status colors (bold applied in output)
  COLOR_CREATED=$(tput setaf 226)    # bright yellow
  COLOR_OPEN=$(tput setaf 255)       # white
  COLOR_CLOSED=$(tput setaf 46)      # bright green
  COLOR_REOPENED=$(tput setaf 39)    # cyan (blue-ish)
  COLOR_UPCOMING=$(tput setaf 214)   # orange
  COLOR_OVERDUE=$(tput setaf 99)     # purple
  COLOR_FAILED=$(tput setaf 196)     # red
  COLOR_SKIPPED=$(tput setaf 244)    # gray
else
  BOLD=""; RESET=""; UNDERLINE=""
  COLOR_HEADER=""; COLOR_PHASE1=""; COLOR_PHASE2=""; COLOR_SUMMARY=""; COLOR_TIMESTAMP=""; COLOR_DIVIDER=""
  COLOR_CREATED=""; COLOR_OPEN=""; COLOR_CLOSED=""; COLOR_REOPENED=""; COLOR_UPCOMING=""; COLOR_OVERDUE=""; COLOR_FAILED=""; COLOR_SKIPPED=""
fi

# Icons / Symbols according to new philosophy
ICON_CREATED="✔"
ICON_SKIPPED="↻"
ICON_FAILED="✗"
ICON_OPEN="◌"
ICON_CLOSED="☑"
ICON_REOPENED="⟳"
ICON_UPCOMING="▶"
ICON_ONTRACK="➣"
ICON_OVERDUE="!"

SYM_CREATED="🟡"
SYM_SKIPPED="⚫"
SYM_FAILED="🔴"
SYM_OPEN="⚪"
SYM_CLOSED="🟢"
SYM_REOPENED="🔵"
SYM_UPCOMING="🟠"
SYM_ONTRACK="⚪"      # On track shares white ball with Open
SYM_OVERDUE="🟣"

BLOCK_CREATED="🟨"
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

print_header() {
  echo
  echo -e "${COLOR_HEADER}${BOLD}╔══════════════════════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${COLOR_HEADER}${BOLD}║                      GitHub Milestone Manager - Ultimate Edition                 ║${RESET}"
  echo -e "${COLOR_HEADER}${BOLD}╚══════════════════════════════════════════════════════════════════════════════════╝${RESET}"
  echo
}

print_section() {
  local title="$1" color="$2"
  echo
  echo -e "${COLOR_DIVIDER}${BOLD}${DIVIDER}${RESET}"
  echo -e "${color}${BOLD}❯ ${title}${RESET}"
  echo -e "${COLOR_DIVIDER}${BOLD}${DIVIDER}${RESET}"
}

print_subsection() {
  local title="$1" color="$2"
  echo
  echo -e "${color}${BOLD}${SUBDIVIDER}${RESET}"
  echo -e "${color}${BOLD}${title}${RESET}"
  echo -e "${color}${BOLD}${SUBDIVIDER}${RESET}"
}

print_aligned_status() {
  local icon="$1" color="$2" title="$3" arrow_msg="$4" timestamp="$5"
  local title_width="${TITLE_WIDTH:-60}"

  # Get total terminal columns, default to 100 if unavailable
  local term_cols=$(tput cols 2>/dev/null || echo 100)

  # Format the main left-aligned string
  local left_str=$(printf "%b${BOLD}%s %-*s %s%b" "$color" "$icon" "$title_width" "$title" "$arrow_msg" "$RESET")
  local right_str=$(printf "${COLOR_TIMESTAMP}[%s]${RESET}" "$timestamp")

  # Calculate visible length of left string (stripping ANSI codes for math)
  # Basic cross-platform regex for ANSI escape sequences
  local clean_left=$(echo -e "$left_str" | sed 's/\x1b\[[0-9;]*m//g')
  local clean_right="[$timestamp]"
  local padding=$(( term_cols - ${#clean_left} - ${#clean_right} ))

  # Ensure padding isn't negative
  (( padding < 1 )) && padding=1

  printf "%s%*s%s\n" "$left_str" "$padding" "" "$right_str"
}

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
      T) printf "%b%s%b" "${COLOR_OPEN}" "${BLOCK_ONTRACK}" "${RESET}" ;;   # On track uses white
      V) printf "%b%s%b" "${COLOR_OVERDUE}" "${BLOCK_OVERDUE}" "${RESET}" ;;
      *) printf " " ;;
    esac
  done
  printf "] 100%% [%d/%d]\n" "${#statuses[@]}" "${#statuses[@]}"
}

print_creation_summary() {
  local created="$1" skipped="$2" failed="$3"
  echo
  echo -e "${COLOR_PHASE1}${BOLD}${SUBDIVIDER}${RESET}"
  echo -e "${COLOR_SUMMARY}${BOLD}📝 Creation Summary${RESET}"
  echo -e "${COLOR_PHASE1}${BOLD}${SUBDIVIDER}${RESET}"
  printf "${COLOR_CREATED}${BOLD}${ICON_CREATED} Created ${SYM_CREATED} ⇒ %s${RESET}  |  " "${COLOR_CREATED}${BOLD}${created}${RESET}"
  printf "${COLOR_SKIPPED}${BOLD}${ICON_SKIPPED} Skipped ${SYM_SKIPPED} ⇒ %s${RESET}  |  " "${COLOR_SKIPPED}${BOLD}${skipped}${RESET}"
  printf "${COLOR_FAILED}${BOLD}${ICON_FAILED} Failure ${SYM_FAILED} ⇒ %s${RESET}\n" "${COLOR_FAILED}${BOLD}${failed}${RESET}"
}

print_sync_summary() {
  local created="$1" skipped="$2" failed="$3" open="$4" closed="$5" reopened="$6"
  echo
  echo -e "${COLOR_PHASE1}${BOLD}${SUBDIVIDER}${RESET}"
  echo -e "${COLOR_SUMMARY}${BOLD}⚙ Synchronization Results${RESET}"
  echo -e "${COLOR_PHASE1}${BOLD}${SUBDIVIDER}${RESET}"
  printf "${COLOR_CREATED}${BOLD}${ICON_CREATED} Created ${SYM_CREATED} ⇒ %s${RESET}  |  " "${COLOR_CREATED}${BOLD}${created}${RESET}"
  printf "${COLOR_SKIPPED}${BOLD}${ICON_SKIPPED} Skipped ${SYM_SKIPPED} ⇒ %s${RESET}  |  " "${COLOR_SKIPPED}${BOLD}${skipped}${RESET}"
  printf "${COLOR_FAILED}${BOLD}${ICON_FAILED} Failure ${SYM_FAILED} ⇒ %s${RESET}\n" "${COLOR_FAILED}${BOLD}${failed}${RESET}"
  printf "${COLOR_OPEN}${BOLD}${ICON_OPEN} Open ${SYM_OPEN} ⇒ %s${RESET}  |  " "${COLOR_OPEN}${BOLD}${open}${RESET}"
  printf "${COLOR_CLOSED}${BOLD}${ICON_CLOSED} Closed ${SYM_CLOSED} ⇒ %s${RESET}  |  " "${COLOR_CLOSED}${BOLD}${closed}${RESET}"
  printf "${COLOR_REOPENED}${BOLD}${ICON_REOPENED} Reopened ${SYM_REOPENED} ⇒ %s${RESET}\n" "${COLOR_REOPENED}${BOLD}${reopened}${RESET}"
}

print_health_summary() {
  local upcoming="$1" on_track="$2" overdue="$3" closed="$4" reopened="$5"
  echo
  echo -e "${COLOR_PHASE2}${BOLD}${SUBDIVIDER}${RESET}"
  echo -e "${COLOR_SUMMARY}${BOLD}🔮 Health Overview${RESET}"
  echo -e "${COLOR_PHASE2}${BOLD}${SUBDIVIDER}${RESET}"
  printf "${COLOR_UPCOMING}${BOLD}${ICON_UPCOMING} Upcoming ${SYM_UPCOMING} ⇒ %s${RESET}  |  " "${COLOR_UPCOMING}${BOLD}${upcoming}${RESET}"
  printf "${COLOR_OPEN}${BOLD}${ICON_ONTRACK} On Track ${SYM_ONTRACK} ⇒ %s${RESET}  |  " "${COLOR_OPEN}${BOLD}${on_track}${RESET}"
  printf "${COLOR_OVERDUE}${BOLD}${ICON_OVERDUE} Overdue ${SYM_OVERDUE} ⇒ %s${RESET}\n" "${COLOR_OVERDUE}${BOLD}${overdue}${RESET}"
  printf "${COLOR_CLOSED}${BOLD}${ICON_CLOSED} Closed ${SYM_CLOSED} ⇒ %s${RESET}  |  " "${COLOR_CLOSED}${BOLD}${closed}${RESET}"
  printf "${COLOR_REOPENED}${BOLD}${ICON_REOPENED} Reopened ${SYM_REOPENED} ⇒ %s${RESET}\n" "${COLOR_REOPENED}${BOLD}${reopened}${RESET}"
}

# -------------------------
# GitHub API wrapper
# -------------------------
gh_api() {
  local fatal_on_error="${1:-true}"
  shift || true
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] gh api $*" >&2
    if [[ "$*" == *" -X POST"* ]] || [[ "$*" == *" -X PATCH"* ]]; then
      echo "{}"
    else
      echo "[]"
    fi
    return 0
  fi
  local output
  output=$(gh api "$@" 2>&1) || {
    local status=$?
    if [[ "$output" == *"HTTP 404"* ]]; then
      echo -e "${COLOR_FAILED}${BOLD}Error: Resource not found.${RESET}" >&2
      if [ "$fatal_on_error" = true ]; then exit 1; else return 1; fi
    elif [[ "$output" == *"HTTP 401"* ]] || [[ "$output" == *"HTTP 403"* ]]; then
      echo -e "${COLOR_FAILED}${BOLD}Authentication error. Run 'gh auth login'.${RESET}" >&2
      if [ "$fatal_on_error" = true ]; then exit 1; else return 1; fi
    else
      echo -e "${COLOR_FAILED}${BOLD}GitHub API error (exit $status):${RESET}" >&2
      echo "$output" >&2
      if [ "$fatal_on_error" = true ]; then exit $status; else return $status; fi
    fi
  }
  echo "$output"
}

fetch_existing_milestones() {
  gh_api true "repos/$OWNER/$REPO/milestones?state=all" --paginate
}

create_github_milestone() {
  local title="$1" description="$2" due_on="$3" state="$4"
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] create milestone: title='$title' state='$state' due_on='$due_on'" >&2
    echo "{\"number\": 9999}"
    return 0
  fi
  gh_api true "repos/$OWNER/$REPO/milestones" -X POST \
    -f "title=$title" \
    -f "description=$description" \
    -f "due_on=$due_on" \
    -f "state=$state"
}

update_github_milestone() {
  local number="$1" title="$2" description="$3" due_on="$4" state="$5"
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] update milestone: #$number title='$title' state='$state' due_on='$due_on'" >&2
    return 0
  fi
  gh_api false "repos/$OWNER/$REPO/milestones/$number" -X PATCH \
    ${title:+-f "title=$title"} \
    ${description:+-f "description=$description"} \
    ${due_on:+-f "due_on=$due_on"} \
    ${state:+-f "state=$state"} 2>/dev/null || return 1
}

get_milestone_issues() {
  local milestone_number="$1"
  gh_api false "repos/$OWNER/$REPO/issues?milestone=$milestone_number&state=all" --paginate 2>/dev/null || echo "[]"
}

update_milestone_emoji() {
  local milestone_number="$1" status="$2"
  local emoji=""
  case "$status" in
    "Upcoming") emoji="🟠" ;;
    "On track") emoji="⚪" ;;
    "Closed")   emoji="🟢" ;;
    "Overdue")  emoji="🟣" ;;
    "Reopened") emoji="🔵" ;;
    *) return 0 ;;
  esac
  local current_desc
  current_desc=$(gh_api false "repos/$OWNER/$REPO/milestones/$milestone_number" | jq -r '.description // ""' 2>/dev/null || echo "")
  clean_desc=$(echo "$current_desc" | sed 's/^[🟡⚪🟢🔵🟠🟣🔴⚫] //' | sed 's/^[🟡⚪🟢🔵🟠🟣🔴⚫]//')
  local new_desc="$emoji $clean_desc"
  if [[ "$current_desc" != "$new_desc" ]]; then
    update_github_milestone "$milestone_number" "" "$new_desc" "" "" >/dev/null 2>&1 || true
  fi
}

# -------------------------
# Core logic
# -------------------------
process_milestones() {
  local created_count=0 skipped_count=0 failed_count=0
  local open_count=0 closed_count=0 reopened_count=0 auto_closed_count=0
  local upcoming_count=0 on_track_count=0 overdue_count=0
  local total_issues=0 open_issues_total=0

  declare -a creation_statuses=() state_statuses=() health_statuses=()
  declare -a existing_list=()

  if [ ! -f "$MILESTONE_FILE" ]; then
    echo -e "${COLOR_FAILED}${BOLD}Error: Milestones file not found: $MILESTONE_FILE${RESET}"
    exit 1
  fi
  total_milestones=$(jq 'length' "$MILESTONE_FILE" 2>/dev/null || echo "0")
  if [ "$total_milestones" -eq 0 ]; then
    echo -e "${COLOR_FAILED}${BOLD}Error: Milestones file is empty or invalid JSON: $MILESTONE_FILE${RESET}"
    exit 1
  fi

  # Precompute max title length for alignment
  max_title_len=0
  while IFS= read -r title; do
    len=${#title}
    (( len > max_title_len )) && max_title_len=$len
  done < <(jq -r '.[].title' "$MILESTONE_FILE")
  TITLE_WIDTH=$(( max_title_len + 2 ))

  existing_raw=$(fetch_existing_milestones)
  existing_milestones=$(echo "$existing_raw" | jq -c '.[]' 2>/dev/null || echo "")

  # PHASE 1: Create missing milestones
  print_section "PHASE 1: MILESTONE SYNCHRONIZATION" "$COLOR_PHASE1"
  echo -e "${COLOR_PHASE1}${BOLD}🗘 Processing milestones...${RESET}"
  print_subsection "❯ CREATE MILESTONES" "$COLOR_PHASE1"

  index=0
  while IFS= read -r milestone; do
    title=$(jq -r '.title' <<< "$milestone")
    description=$(jq -r '.description // ""' <<< "$milestone")
    due_on=$(jq -r '.due_on // empty' <<< "$milestone")
    state=$(jq -r '.state // "open"' <<< "$milestone")

    if [ -z "$due_on" ]; then
      due_on=$(compute_due_date "$START_DATE" "$((index * SPACING_DAYS))" "$DEFAULT_DUE_TIME")
    fi

    existing=$(jq -c --arg t "$title" 'select(.title == $t)' <<< "$existing_milestones" 2>/dev/null || true)
    if [ -z "$existing" ]; then
      if output=$(create_github_milestone "$title" "$description" "$due_on" "$state" 2>&1); then
        arrow_msg="→ ${SYM_CREATED} ⇒ Created"
        print_aligned_status "$ICON_CREATED" "$COLOR_CREATED" "$title" "$arrow_msg" "$(timestamp_now)"
        creation_statuses+=("C")
        created_count=$((created_count+1))
      else
        arrow_msg="→ ${SYM_FAILED} ⇒ Failed: ${output:0:80}"
        print_aligned_status "$ICON_FAILED" "$COLOR_FAILED" "$title" "$arrow_msg" "$(timestamp_now)"
        creation_statuses+=("F")
        failed_count=$((failed_count+1))
      fi
    else
      arrow_msg="→ ${SYM_SKIPPED} ⇒ Existing"
      print_aligned_status "$ICON_SKIPPED" "$COLOR_SKIPPED" "$title" "$arrow_msg" "$(timestamp_now)"
      creation_statuses+=("S")
      skipped_count=$((skipped_count+1))
    fi
    index=$((index+1))
  done < <(jq -c '.[]' "$MILESTONE_FILE")

  print_progress_bar creation_statuses
  print_creation_summary "$created_count" "$skipped_count" "$failed_count"

  # PHASE 1b: Update metadata & reopening
  echo -e "\n${COLOR_PHASE1}${BOLD}🌀 Fetching milestones from GitHub...${RESET} $(timestamp_now)"
  print_subsection "❯ UPDATE METADATA & REOPENING" "$COLOR_PHASE1"

  existing_raw_updated=$(fetch_existing_milestones)
  existing_milestones_updated=$(echo "$existing_raw_updated" | jq -c '.[]' 2>/dev/null || echo "")
  if [ -z "$existing_milestones_updated" ]; then
    existing_list=()
  else
    mapfile -t existing_list < <(echo "$existing_milestones_updated" | sed '/^\s*$/d')
  fi

  declare -A open_issues_cache
  declare -A closed_issues_cache

  for m in "${existing_list[@]}"; do
    title=$(jq -r '.title' <<< "$m")
    state=$(jq -r '.state' <<< "$m")
    number=$(jq -r '.number' <<< "$m")
    ts="$(timestamp_now)"

    issues_raw=$(get_milestone_issues "$number")
    open_issues=0
    closed_issues=0
    if [ -n "$issues_raw" ] && [ "$issues_raw" != "[]" ]; then
      while IFS= read -r issue; do
        issue_state=$(jq -r '.state' <<< "$issue" 2>/dev/null || echo "unknown")
        if [ "$issue_state" = "open" ]; then
          open_issues=$((open_issues+1))
        elif [ "$issue_state" = "closed" ]; then
          closed_issues=$((closed_issues+1))
        fi
      done < <(echo "$issues_raw" | jq -c '.[]' 2>/dev/null || true)
    fi
    open_issues_cache[$number]=$open_issues
    closed_issues_cache[$number]=$closed_issues
    total=$((open_issues + closed_issues))

    original_state="$state"
    new_state="$state"

    if [ "$state" = "closed" ] && { [ "$open_issues" -gt 0 ] || [ "$total" -eq 0 ]; }; then
      if update_github_milestone "$number" "" "" "" "open" >/dev/null 2>&1; then
        new_state="open"
        arrow_msg="→ ${SYM_REOPENED} ⇒ Reopened"
        print_aligned_status "$ICON_REOPENED" "$COLOR_REOPENED" "$title" "$arrow_msg" "$ts"
        state_statuses+=("R")
        reopened_count=$((reopened_count+1))
      fi
    elif [ "$state" = "open" ] && [ "$open_issues" -eq 0 ] && [ "$total" -gt 0 ]; then
      if update_github_milestone "$number" "" "" "" "closed" >/dev/null 2>&1; then
        new_state="closed"
        arrow_msg="→ ${SYM_CLOSED} ⇒ Auto-Closed"
        print_aligned_status "$ICON_CLOSED" "$COLOR_CLOSED" "$title" "$arrow_msg" "$ts"
        state_statuses+=("D")
        auto_closed_count=$((auto_closed_count+1))
      fi
    fi

    if [ "$new_state" != "$original_state" ]; then
      m=$(jq -c --arg state "$new_state" '.state = $state' <<< "$m")
      state="$new_state"
    fi

    if [ "$state" = "open" ]; then
      arrow_msg="→ ${SYM_OPEN} ⇒ Open"
      print_aligned_status "$ICON_OPEN" "$COLOR_OPEN" "$title" "$arrow_msg" "$ts"
      state_statuses+=("O")
      open_count=$((open_count+1))
    else
      arrow_msg="→ ${SYM_CLOSED} ⇒ Closed"
      print_aligned_status "$ICON_CLOSED" "$COLOR_CLOSED" "$title" "$arrow_msg" "$ts"
      state_statuses+=("D")
      closed_count=$((closed_count+1))
    fi
  done

  print_progress_bar state_statuses
  print_sync_summary "$created_count" "$skipped_count" "$failed_count" "$open_count" "$closed_count" "$reopened_count"

  # PHASE 2: Health management
  print_section "PHASE 2: MILESTONE HEALTH MANAGEMENT" "$COLOR_PHASE2"
  echo -e "${COLOR_PHASE2}${BOLD}🌟 Analyzing milestone health...${RESET} $(timestamp_now)"
  print_subsection "❯ Milestone Status Review" "$COLOR_PHASE2"

  # Collect open milestones for upcoming detection
  declare -a open_diffs=()
  declare -a open_ms_numbers=()
  for m in "${existing_list[@]}"; do
    state=$(jq -r '.state' <<< "$m")
    [ "$state" = "closed" ] && continue
    number=$(jq -r '.number' <<< "$m")
    due_on=$(jq -r '.due_on // empty' <<< "$m")
    if [ -n "$due_on" ]; then
      if $HAVE_GNU_DATE; then
        due_ts=$(date -d "$due_on" +%s 2>/dev/null || echo 0)
      else
        due_ts=$(python3 -c "from datetime import datetime; print(int(datetime.fromisoformat('$due_on').timestamp()))" 2>/dev/null || echo 0)
      fi
      now_ts=$(date +%s)
      diff_days=$(( due_ts > 0 ? (due_ts - now_ts) / 86400 : 99999 ))
    else
      diff_days=99999
    fi
    open_diffs+=("$diff_days")
    open_ms_numbers+=("$number")
  done

  closest_index=-1
  closest_val=99999
  for i in "${!open_diffs[@]}"; do
    val=${open_diffs[$i]}
    if [ "$val" -ge 0 ] && [ "$val" -lt "$closest_val" ]; then
      closest_val=$val
      closest_index=$i
    fi
  done

  for i in "${!existing_list[@]}"; do
    m="${existing_list[$i]}"
    number=$(jq -r '.number' <<< "$m")
    title=$(jq -r '.title' <<< "$m")
    state=$(jq -r '.state' <<< "$m")
    due_on=$(jq -r '.due_on // empty' <<< "$m")

    open_issues=${open_issues_cache[$number]:-0}
    closed_issues=${closed_issues_cache[$number]:-0}
    total=$((open_issues + closed_issues))
    total_issues=$((total_issues + total))
    open_issues_total=$((open_issues_total + open_issues))

    # Compute status, primary color, and leading icon
    if [ "$state" = "closed" ]; then
      health_status="Closed"
      icon="$SYM_CLOSED $ICON_CLOSED"
      leading_icon="$ICON_CLOSED"
      color="$COLOR_CLOSED"
      health_statuses+=("D")
    else
      # Check if this open milestone is the closest upcoming
      is_closest=false
      for j in "${!open_ms_numbers[@]}"; do
        if [ "${open_ms_numbers[$j]}" -eq "$number" ] && [ "$j" -eq "$closest_index" ]; then
          is_closest=true
          break
        fi
      done

      if [ -n "$due_on" ] && [ "${diff_days:-99999}" -lt 0 ]; then
        health_status="Overdue"
        icon="$SYM_OVERDUE $ICON_OVERDUE"
        leading_icon="$ICON_OVERDUE"
        color="$COLOR_OVERDUE"
        health_statuses+=("V")
        overdue_count=$((overdue_count+1))
      elif [ "$is_closest" = true ]; then
        health_status="Upcoming"
        icon="$SYM_UPCOMING $ICON_UPCOMING"
        leading_icon="$ICON_UPCOMING"
        color="$COLOR_UPCOMING"
        health_statuses+=("P")
        upcoming_count=$((upcoming_count+1))
      else
        health_status="On track"
        icon="$SYM_ONTRACK $ICON_ONTRACK"
        leading_icon="$ICON_ONTRACK"
        color="$COLOR_OPEN"        # On track uses white text
        health_statuses+=("T")
        on_track_count=$((on_track_count+1))
      fi
    fi

    # Build due date info with color based on health_status
    if [ -n "$due_on" ]; then
      due_date_fmt=$(echo "$due_on" | cut -d'T' -f1)
      if $HAVE_GNU_DATE; then
        diff_days=$(date -d "$due_on" +%s 2>/dev/null | awk '{print int(($1 - now)/86400)}' now=$(date +%s) || echo "?")
      else
        diff_days=$(python3 -c "from datetime import datetime; d=datetime.fromisoformat('$due_on'); now=datetime.now(); print((d-now).days)" 2>/dev/null || echo "?")
      fi
      # Due date color follows the status color, except Closed uses green
      if [ "$health_status" = "Closed" ]; then
        due_color="$COLOR_CLOSED"
      else
        due_color="$color"
      fi
      due_info="${due_color}${BOLD}→ $due_date_fmt (due in ${diff_days:-?} days)${RESET}"
    else
      due_info="${COLOR_TIMESTAMP}→ No due date${RESET}"
    fi

    update_milestone_emoji "$number" "$health_status" 2>/dev/null || true

    # Modern Framework Tree Output for Issues
    arrow_msg="$due_info ⇒ ${color}${BOLD}${icon} ${health_status}${RESET}"

    print_aligned_status "$leading_icon" "$color" "$title" "$arrow_msg" "$(timestamp_now)"
    echo -e "  ${color}└──${RESET} ${COLOR_OPEN}Issues:${RESET} ${open_issues} Open, ${closed_issues} Closed\n"
  done

  [ ${#health_statuses[@]} -gt 0 ] && print_progress_bar health_statuses
  print_health_summary "$upcoming_count" "$on_track_count" "$overdue_count" "$closed_count" "$reopened_count"

# FINAL SUMMARY (Original layout with colored category & notes)
  print_section "FINAL SUMMARY" "$COLOR_SUMMARY"
  echo
  printf "${COLOR_SUMMARY}${BOLD}%-20s %-12s %-30s${RESET}\n" "Category" "Count" "Notes"
  printf "${COLOR_SUMMARY}%-20s %-12s %-30s${RESET}\n" "──────────────────" "──────────" "──────────────────────────────"

  # Format specifier: %b applies color, %s applies the padding, %b resets it
  local ROW_FMT="%b%-20s%b %b%-12s%b %b%-30s%b\n"

  printf "$ROW_FMT" "${COLOR_SUMMARY}"  "Total Milestones" "${RESET}" "${COLOR_SUMMARY}${BOLD}"  "$total_milestones"  "${RESET}" "${COLOR_SUMMARY}"  "All milestones processed"       "${RESET}"
  printf "$ROW_FMT" "${COLOR_CREATED}"  "Created"          "${RESET}" "${COLOR_CREATED}${BOLD}"  "$created_count"     "${RESET}" "${COLOR_CREATED}"  "New milestones created"         "${RESET}"
  printf "$ROW_FMT" "${COLOR_SKIPPED}"  "Skipped"          "${RESET}" "${COLOR_SKIPPED}${BOLD}"  "$skipped_count"     "${RESET}" "${COLOR_SKIPPED}"  "Existing milestones skipped"    "${RESET}"
  printf "$ROW_FMT" "${COLOR_REOPENED}" "Reopened"         "${RESET}" "${COLOR_REOPENED}${BOLD}" "$reopened_count"    "${RESET}" "${COLOR_REOPENED}" "Incomplete milestones reopened" "${RESET}"
  printf "$ROW_FMT" "${COLOR_CLOSED}"   "Auto-Closed"      "${RESET}" "${COLOR_CLOSED}${BOLD}"   "$auto_closed_count" "${RESET}" "${COLOR_CLOSED}"   "Completed milestones closed"    "${RESET}"
  printf "$ROW_FMT" "${COLOR_CLOSED}"   "Total Closed"     "${RESET}" "${COLOR_CLOSED}${BOLD}"   "$closed_count"      "${RESET}" "${COLOR_CLOSED}"   "All closed milestones"          "${RESET}"
  printf "$ROW_FMT" "${COLOR_PHASE1}"   "Issues Tracked"   "${RESET}" "${COLOR_PHASE1}${BOLD}"   "$total_issues"      "${RESET}" "${COLOR_PHASE1}"   "Total issues across milestones" "${RESET}"

  echo

  if [ "$open_issues_total" -gt 0 ]; then
    echo -e "${COLOR_FAILED}${BOLD}❗ Attention: There are $open_issues_total open issues across all milestones${RESET} $(timestamp_now)"
  fi

  # Completion message - now light green bold
  echo -e "\n${COLOR_CLOSED}${BOLD}🎉 Milestone management completed successfully for ${UNDERLINE}${OWNER}/${REPO}${RESET}"
  echo -e "\n${COLOR_SUMMARY}${BOLD}💫 Thank you for using GitHub Milestone Manager!${RESET}"

  echo -e "\n${COLOR_PHASE1}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${COLOR_PHASE2}${BOLD}                           Author Details                                  ${RESET}"
  echo -e "${COLOR_PHASE1}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${COLOR_CREATED}${BOLD}ANUJ KUMAR${RESET}"
  echo -e "${COLOR_PHASE1}🏅 QA Consultant & Test Automation Architect${RESET}"
  echo -e "${COLOR_UPCOMING}📧 Email: ${COLOR_PHASE2}anujpatiyal@live.in${RESET}"
  echo -e "${COLOR_UPCOMING}🔗 ${COLOR_PHASE2}https://www.linkedin.com/in/anuj-kumar-qa/${RESET}"

  echo -e "\n${COLOR_TIMESTAMP}Completed at: $(timestamp_now)${RESET}\n"
}

# -------------------------
# Main
# -------------------------
main() {
  if ! command -v gh >/dev/null 2>&1; then
    echo -e "${COLOR_FAILED}${BOLD}Error: GitHub CLI (gh) not installed.${RESET}"
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo -e "${COLOR_FAILED}${BOLD}Error: jq not installed.${RESET}"
    exit 1
  fi
  if [ "$DRY_RUN" = false ]; then
    if ! gh auth status >/dev/null 2>&1; then
      echo -e "${COLOR_FAILED}${BOLD}Error: GitHub CLI not authenticated. Run 'gh auth login'.${RESET}"
      exit 1
    fi
  fi

  if [ "$NO_CLEAR" = false ] && [ -t 1 ]; then
    clear
  fi

  print_header
  # Repository string now appears in bright yellow bold
  echo -e "🎯 ${COLOR_PHASE1}Initializing GitHub Milestone Manager for: ${COLOR_CREATED}${BOLD}${OWNER}/${REPO}${RESET} $(timestamp_now)"
  echo -e "🔧 ${COLOR_PHASE1}Configuration    ⇒ $(timestamp_now)"
  echo -e "  💡 Start Date     ⇒ ${COLOR_UPCOMING}${START_DATE}${RESET}"
  echo -e "  ⇄ Spacing Days    ⇒ ${COLOR_UPCOMING}${SPACING_DAYS}${RESET}"
  echo -e "  🕛 Default Time   ⇒ ${COLOR_UPCOMING}${DEFAULT_DUE_TIME}${RESET}"
  echo -e "  𓊕 Dry Run         ⇒ ${COLOR_UPCOMING}${DRY_RUN}${RESET}"

  process_milestones
}

main "$@"
