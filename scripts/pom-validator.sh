#!/usr/bin/env bash
# Ultimate POM Validator v1.4 - Enhanced UI/UX with beautiful reports
# Completed + formatting improvements + rich HTML reports

# === CONFIGURATION ===
POM_FILE="${POM_FILE:-pom.xml}"
REPORTS_DIR="${REPORTS_DIR:-./Reports}"
HTML_REPORT="${HTML_REPORT:-true}"
DEPENDENCY_GRAPH="${DEPENDENCY_GRAPH:-false}"
STRICT_MODE="${STRICT_MODE:-false}"
VERBOSE="${VERBOSE:-false}"

# === COLORS & STYLE (ANSI) ===
BOLD='\033[1m'
RESET='\033[0m'

# Status colors
PASS_COLOR='\033[1;38;5;46m'    # bright green
WARN_COLOR='\033[1;38;5;208m'   # orange
FAIL_COLOR='\033[1;38;5;196m'   # red
INFO_COLOR='\033[1;38;5;33m'    # blue
SKIP_COLOR='\033[1;38;5;240m'   # grey/blackish

# Project info colors
VERSION_COLOR='\033[1;38;5;93m'    # purple
STAGE_COLOR='\033[1;38;5;220m'     # yellow
MODE_COLOR='\033[1;38;5;45m'       # teal

# Section colors
SECTION_PURPLE='\033[1;38;5;141m'   # brighter magenta
SECTION_CYAN='\033[1;38;5;51m'      # vibrant cyan
SECTION_BLUE='\033[1;38;5;75m'      # ocean blue
HEADER_BLUE='\033[1;38;5;39m'       # header blue
TOTAL_COLOR='\033[1;38;5;117m'      # light blue
THANKS_COLOR='\033[1;38;5;219m'     # pink

# Author highlight
AUTHOR_BG='\033[48;5;236m'
AUTHOR_FG='\033[1;38;5;229m'
AUTHOR_NAME_COLOR='\033[1;38;5;129m'     # purple
AUTHOR_ROLE_COLOR='\033[1;38;5;208m'     # orange
AUTHOR_EMAIL_COLOR='\033[1;38;5;39m'     # blue
AUTHOR_LINK_COLOR='\033[1;38;5;255m'     # white

# === ICONS ===
PASS_ICON="🟢"
WARN_ICON="🟠"
FAIL_ICON="🔴"
INFO_ICON="🔵"
SKIP_ICON="⚫"
ARROW_ICON="⇒"

PROJECT_ICON="📜"
STAGE_ICON="📸"
MODE_ICON="⚔️"

# Progress blocks
PB_PASS="🟩"
PB_FAIL="🟥"
PB_INFO="🟦"
PB_WARN="🟧"
PB_SKIP="⬛"

# Author info
AUTHOR_NAME="ANUJ KUMAR"
AUTHOR_ROLE="QA Consultant & Test Automation Engineer"
AUTHOR_EMAIL="anujpatiyal@live.in"
AUTHOR_LINKEDIN="https://www.linkedin.com/in/anuj-kumar-qa/"

# === MILESTONE MAP ===
declare -A MILESTONE_MAP=(
  ["v0.0.0"]="Initial Setup"
  ["v0.1.0"]="Basic Testing"
  ["v0.2.0"]="CI Integration"
  ["v0.3.0"]="Logging Setup"
  ["v0.4.0"]="Exception Handling"
  ["v0.5.0"]="Driver Management"
  ["v0.6.0"]="POM Structure"
  ["v0.7.0"]="Wait Utilities"
  ["v0.8.0"]="Screenshot Support"
  ["v0.9.0"]="TestNG Listeners"
  ["v1.0.0"]="Allure Reporting"
  ["v1.1.0"]="Retry Mechanism"
  ["v1.10.0"]="Stable Release"
)

# === VERSION REQUIREMENTS ===
declare -A VERSION_REQUIREMENTS=(
  ["selenium-java"]="4.0.0"
  ["testng"]="7.0.0"
  ["log4j-core"]="2.0.0"
  ["log4j-api"]="2.0.0"
  ["log4j-slf4j2-impl"]="2.0.0"
  ["allure-testng"]="2.0.0"
  ["webdrivermanager"]="5.0.0"
  ["maven-surefire-plugin"]="3.0.0"
  ["maven-compiler-plugin"]="3.0.0"
  ["maven-clean-plugin"]="3.0.0"
  ["maven-resources-plugin"]="3.0.0"
  ["maven-jar-plugin"]="3.0.0"
  ["maven-install-plugin"]="3.0.0"
  ["java.version"]="17"
)

# === MILESTONE-GATED REQUIREMENTS ===
declare -A PROJECT_INFO_REQUIREMENTS=(
  ["groupId"]="v0.0.0"
  ["artifactId"]="v0.0.0"
  ["version"]="v0.0.0"
  ["modelVersion"]="v0.0.0"
  ["encoding"]="v0.0.0"
  ["java"]="v0.1.0"
)

declare -A DEPENDENCY_REQUIREMENTS=(
  ["selenium-java"]="v0.1.0"
  ["testng"]="v0.1.0"
  ["log4j-core"]="v0.4.0"
  ["log4j-api"]="v0.4.0"
  ["log4j-slf4j2-impl"]="v0.4.0"
  ["allure-testng"]="v1.0.0"
  ["webdrivermanager"]="v0.5.0"
)

declare -A PLUGIN_REQUIREMENTS=(
  ["maven-compiler-plugin"]="v0.1.0"
  ["maven-surefire-plugin"]="v0.5.0"
  ["maven-clean-plugin"]="v0.1.0"
  ["maven-resources-plugin"]="v0.1.0"
  ["maven-jar-plugin"]="v0.1.0"
  ["maven-install-plugin"]="v0.1.0"
)

# === CHECK REGISTRY ===
declare -A CHECK_FUNCS=(
    [project_info]=check_project_info
    [dependencies]=check_dependencies
    [plugins]=check_plugins
)

declare -a DEFAULT_CHECKS=(
    "project_info"
    "dependencies"
    "plugins"
)

# === TRACKING ===
declare -A counts=( ["pass"]=0 ["warn"]=0 ["fail"]=0 ["info"]=0 ["skip"]=0 )
declare -a ALL_RESULTS=()
completed_checks=0
total_checks=0
start_time=$(date +%s)

# Global per-check status array
declare -a CHECK_STATUS_ARRAY=()

# Per-category stored lines
declare -A CATEGORY_RESULTS=(
  ["Project Information"]=""
  ["Dependencies"]=""
  ["Plugins"]=""
)

# === UTILITY FUNCTIONS ===
get_display_width() { echo -n "$1" | wc -m; }

validate_xml() {
  if ! command -v xmllint &>/dev/null; then
    echo -e "${WARN_COLOR}${BOLD}⚠ xmllint not found; skipping strict XML validation${RESET}"
    return 0
  fi
  if ! xmllint --noout "$POM_FILE" 2>/dev/null; then
    echo -e "${FAIL_COLOR}${BOLD}✗ Error: Invalid XML in $POM_FILE${RESET}"
    exit 1
  fi
}

init_output_dir() {
  mkdir -p "$REPORTS_DIR"
  if [[ "$HTML_REPORT" == "true" ]]; then
    cat > "$REPORTS_DIR/pom-validation-report.html" <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>POM Validation Report</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700;800&display=swap" rel="stylesheet">
<style>
:root{
  --bg:#071021; --card:#0c1115; --muted:#9aa7bd; --accent:#6aa0ff;
  --pass:#27ae60; --warn:#f39c12; --fail:#e74c3c; --info:#3498db; --skip:#7f8c8d;
  --purple:#9b7bed; --cyan:#00d1ff; --blue:#6fb3ff; --glass: rgba(255,255,255,0.03);

  /* Status colors */
  --pass-bg: rgba(39, 174, 96, 0.15);
  --warn-bg: rgba(243, 156, 18, 0.15);
  --fail-bg: rgba(231, 76, 60, 0.15);
  --info-bg: rgba(52, 152, 219, 0.15);
  --skip-bg: rgba(127, 140, 141, 0.15);
}
*{box-sizing:border-box;font-family:Inter,system-ui,Segoe UI,Roboto,Arial;}
body{margin:0;background:linear-gradient(180deg,#04101a 0%,var(--bg) 100%);color:#e6eef6;}
.container{max-width:1100px;margin:28px auto;padding:18px;}
.header{display:flex;align-items:center;justify-content:space-between;gap:12px;}
.header-left h1{margin:0;font-weight:800;color:var(--accent);font-size:20px;}
.meta{color:var(--muted);font-size:13px;margin-top:6px}
.card{background:linear-gradient(180deg,var(--card),#071018);border-radius:12px;padding:18px;box-shadow:0 10px 30px rgba(2,6,23,0.7);margin-top:18px}
.section-title{display:flex;align-items:center;gap:10px;font-weight:700;padding:10px;border-radius:8px;color:#fff}
.project-badges{display:flex;gap:10px;align-items:center;margin-top:8px}
.badge{padding:6px 10px;border-radius:999px;font-weight:700;font-size:12px;background:rgba(255,255,255,0.03);color:var(--muted);display:inline-flex;align-items:center;gap:8px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-top:14px}
.table{width:100%;border-collapse:collapse;margin-top:10px;table-layout:fixed}
.table th{background:linear-gradient(90deg,var(--purple),var(--blue));padding:12px;text-align:left;color:#fff;border-radius:6px 6px 0 0}
.table td{padding:10px;border-bottom:1px solid rgba(255,255,255,0.03);font-size:13px;color:#dbe9ff;word-wrap:break-word}
.table th:nth-child(1), .table td:nth-child(1) { width: 30%; }
.table th:nth-child(2), .table td:nth-child(2) { width: 15%; }
.table th:nth-child(3), .table td:nth-child(3) { width: 55%; }

/* Status rows */
.tr-pass { background: var(--pass-bg); }
.tr-warn { background: var(--warn-bg); }
.tr-fail { background: var(--fail-bg); }
.tr-info { background: var(--info-bg); }
.tr-skip { background: var(--skip-bg); }

/* Status badges */
.status-badge {
  display: inline-block;
  padding: 4px 10px;
  border-radius: 12px;
  font-weight: 700;
  font-size: 12px;
  text-align: center;
  min-width: 70px;
}
.badge-pass { background: var(--pass); color: white; }
.badge-warn { background: var(--warn); color: white; }
.badge-fail { background: var(--fail); color: white; }
.badge-info { background: var(--info); color: white; }
.badge-skip { background: var(--skip); color: white; }

.progress-strip{font-size:18px;letter-spacing:2px;margin-top:10px;white-space:nowrap;overflow-x:auto;padding-bottom:5px}
.summary-grid{display:grid;grid-template-columns:repeat(5,1fr);gap:10px;margin-top:12px}
.summary-card{background:#081018;padding:14px;border-radius:10px;text-align:center}
.summary-card .big{font-size:20px;font-weight:800}
.author-card{background:linear-gradient(90deg,#0a1a2a, #0c1825);padding:20px;border-radius:12px;margin-top:20px;color:#e6f2ff;display:flex;gap:20px;align-items:center;border:1px solid rgba(100,150,255,0.1);box-shadow:0 5px 15px rgba(0,0,0,0.3)}
.author-card .avatar{width:64px;height:64px;border-radius:999px;background:linear-gradient(135deg,var(--purple),var(--cyan));display:flex;align-items:center;justify-content:center;font-weight:900;color:#021;font-size:20px}
.small{font-size:13px;color:var(--muted)}
.footer{margin-top:18px;color:var(--muted);font-size:13px;text-align:right}

/* Colored summary cards */
.summary-pass { background: linear-gradient(135deg, rgba(39, 174, 96, 0.2), rgba(39, 174, 96, 0.1)); }
.summary-warn { background: linear-gradient(135deg, rgba(243, 156, 18, 0.2), rgba(243, 156, 18, 0.1)); }
.summary-fail { background: linear-gradient(135deg, rgba(231, 76, 60, 0.2), rgba(231, 76, 60, 0.1)); }
.summary-info { background: linear-gradient(135deg, rgba(52, 152, 219, 0.2), rgba(52, 152, 219, 0.1)); }
.summary-skip { background: linear-gradient(135deg, rgba(127, 140, 141, 0.2), rgba(127, 140, 141, 0.1)); }

@media(max-width:900px){.grid{grid-template-columns:1fr;}.summary-grid{grid-template-columns:repeat(2,1fr)}}
a{color:inherit;text-decoration:none}
</style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="header-left">
        <h1>POM Validation Report</h1>
        <div class="meta">Generated: $(date +"%d-%b-%Y %I:%M:%S %p")</div>
      </div>
      <div class="header-right">
        <div class="badge">Project: <strong style="margin-left:8px">${project_version#v}</strong></div>
        <div class="badge">Stage: <strong style="margin-left:8px">${MILESTONE_MAP["$project_version"]:-"Unknown"}</strong></div>
      </div>
    </div>

    <div class="card">
      <div class="section-title" style="background:linear-gradient(90deg,var(--purple),var(--cyan));padding:14px">
        <div style="font-size:16px">Validation Summary</div>
      </div>

      <div class="grid" style="margin-top:12px">
        <div>
          <div style="font-weight:700;color:#fff">Project Information</div>
          <table class="table">
            <thead>
              <tr>
                <th>Item</th>
                <th>Status</th>
                <th>Message</th>
              </tr>
            </thead>
            <tbody id="report-body-project"></tbody>
          </table>
        </div>
        <div>
          <div style="font-weight:700;color:#fff">Dependencies</div>
          <table class="table">
            <thead>
              <tr>
                <th>Dependency</th>
                <th>Status</th>
                <th>Message</th>
              </tr>
            </thead>
            <tbody id="report-body-deps"></tbody>
          </table>
        </div>
      </div>

      <div style="margin-top:14px">
        <div style="font-weight:700;color:#fff">Plugins</div>
        <table class="table">
          <thead>
            <tr>
              <th>Plugin</th>
              <th>Status</th>
              <th>Message</th>
            </tr>
          </thead>
          <tbody id="report-body-plugins"></tbody>
        </table>
      </div>

      <div class="summary-grid" id="summary-grid">
        <div class="summary-card summary-pass"><div class="big">🟢</div><div style="font-size:12px">Passed</div><div style="font-weight:700" id="html-pass-count">0</div></div>
        <div class="summary-card summary-warn"><div class="big">🟠</div><div style="font-size:12px">Warnings</div><div style="font-weight:700" id="html-warn-count">0</div></div>
        <div class="summary-card summary-fail"><div class="big">🔴</div><div style="font-size:12px">Failures</div><div style="font-weight:700" id="html-fail-count">0</div></div>
        <div class="summary-card summary-info"><div class="big">🔵</div><div style="font-size:12px">Info</div><div style="font-weight:700" id="html-info-count">0</div></div>
        <div class="summary-card summary-skip"><div class="big">⚫</div><div style="font-size:12px">Skipped</div><div style="font-weight:700" id="html-skip-count">0</div></div>
      </div>

      <div id="html-progress-strip" class="progress-strip"></div>
    </div>

    <!-- Author card -->
    <div class="author-card">
      <div class="avatar">AK</div>
      <div>
        <div style="font-weight:900;font-size:18px">${AUTHOR_NAME} <span style="font-size:14px">🏅</span></div>
        <div style="font-weight:700;margin-top:6px;color:#ffcc66">${AUTHOR_ROLE}</div>
        <div class="small" style="margin-top:10px">
          📧 <a href="mailto:${AUTHOR_EMAIL}" style="color:#6fb3ff">${AUTHOR_EMAIL}</a> &nbsp;
          🔗 <a href="${AUTHOR_LINKEDIN}" style="color:#6fb3ff">${AUTHOR_LINKEDIN}</a>
        </div>
      </div>
    </div>

    <div class="footer">Completed: $(date +"%d-%b-%Y %I:%M:%S %p")</div>
  </div>
</body>
</html>
HTML
  fi
}

finalize_html_report() {
  if [[ "$HTML_REPORT" == "true" ]]; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))

    # Replace numeric counters robustly (use -E for extended regex)
    sed -i -E "s/(id=\"html-pass-count\">)[0-9]+/\1${counts["pass"]}/" "$REPORTS_DIR/pom-validation-report.html" 2>/dev/null || true
    sed -i -E "s/(id=\"html-warn-count\">)[0-9]+/\1${counts["warn"]}/" "$REPORTS_DIR/pom-validation-report.html" 2>/dev/null || true
    sed -i -E "s/(id=\"html-fail-count\">)[0-9]+/\1${counts["fail"]}/" "$REPORTS_DIR/pom-validation-report.html" 2>/dev/null || true
    sed -i -E "s/(id=\"html-info-count\">)[0-9]+/\1${counts["info"]}/" "$REPORTS_DIR/pom-validation-report.html" 2>/dev/null || true
    sed -i -E "s/(id=\"html-skip-count\">)[0-9]+/\1${counts["skip"]}/" "$REPORTS_DIR/pom-validation-report.html" 2>/dev/null || true

    # Build progress strip
    local progress_strip=""
    for status in "${CHECK_STATUS_ARRAY[@]}"; do
      case "$status" in
        "P") progress_strip+="🟩" ;;
        "W") progress_strip+="🟧" ;;
        "F") progress_strip+="🟥" ;;
        "I") progress_strip+="🟦" ;;
        "S") progress_strip+="⬛" ;;
      esac
    done

    # Append percentage if we have total_checks > 0
    if (( total_checks > 0 )); then
      local pct=$(( (counts["pass"] * 100) / total_checks ))
      progress_strip+="  ${pct}%"
    fi

    # Replace empty progress container with strip
    sed -i "s|<div id=\"html-progress-strip\" class=\"progress-strip\"></div>|<div id=\"html-progress-strip\" class=\"progress-strip\">$progress_strip</div>|" "$REPORTS_DIR/pom-validation-report.html" 2>/dev/null || true
  fi
}

# Helper functions
get_version_by_artifact_id() {
  local artifact="$1"
  awk "/<artifactId>$artifact<\/artifactId>/,/<\/(plugin|dependency)>/" "$POM_FILE" 2>/dev/null \
    | grep -oP "<version>(.*?)</version>" 2>/dev/null \
    | sed -E 's|<version>(.*)</version>|\1|' 2>/dev/null \
    | head -n1 || true
}
resolve_property() {
  local value="$1"
  if [[ "$value" =~ ^\$\{(.+)\}$ ]]; then
    local key="${BASH_REMATCH[1]}"
    get_tag_value "$key"
  else
    echo "$value"
  fi
}
get_tag_value() {
  local tag="$1"
  grep -oP "<$tag>(.*?)</$tag>" "$POM_FILE" 2>/dev/null | sed -E "s|.*<$tag>(.*)</$tag>.*|\1|" | head -n1 || true
}
version_ge() {
  # Returns true if $1 >= $2 (version compare)
  [ "$1" = "$2" ] && return 0
  [ "$(printf "%s\n%s" "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

# === RECORD RESULT ===
record_result() {
  local status="$1"; local category="$2"; local item="$3"; local message="$4"
  ((counts["$status"]++))
  ((completed_checks++))

  # Map statuses for final strip
  case "$status" in
    pass) CHECK_STATUS_ARRAY+=("P") ;;
    warn) CHECK_STATUS_ARRAY+=("W") ;;
    fail) CHECK_STATUS_ARRAY+=("F") ;;
    info) CHECK_STATUS_ARRAY+=("I") ;;
    skip) CHECK_STATUS_ARRAY+=("S") ;;
    *) CHECK_STATUS_ARRAY+=("I") ;;
  esac

  # Clean message for HTML
  local clean_message
  clean_message=$(echo -e "$message" | sed -E "s/\\\033\[[0-9;]*m//g")

  ALL_RESULTS+=("$status|$category|$item|$clean_message")
  CATEGORY_RESULTS["$category"]+="$status|$item|$clean_message\n"

  if [[ "$HTML_REPORT" == "true" ]]; then
    local tid
    case "$category" in
      "Project Information") tid="report-body-project" ;;
      "Dependencies") tid="report-body-deps" ;;
      "Plugins") tid="report-body-plugins" ;;
      *) tid="report-body-project" ;;
    esac

    # Choose icon for HTML
    local html_icon
    case "$status" in
      pass) html_icon="🟢" ;;
      warn) html_icon="🟠" ;;
      fail) html_icon="🔴" ;;
      info) html_icon="🔵" ;;
      skip) html_icon="⚫" ;;
      *) html_icon="ℹ" ;;
    esac

    # Status badge class
    local badge_class="badge-$status"

    # Row class for background
    local row_class="tr-$status"

    # Append row to HTML table (append after tbody opening)
    sed -i "/id=\"$tid\"/a\\
    <tr class=\"$row_class\"><td><strong>$item</strong></td><td><span class=\"status-badge $badge_class\">$html_icon ${status}</span></td><td>${clean_message}</td></tr>" "$REPORTS_DIR/pom-validation-report.html" 2>/dev/null || true
  fi
}

# === PRINT HELP ===
print_help() {
  echo -e "${BOLD}Usage:${RESET} $0 [options]"
  echo -e "Options:"
  echo -e "  --strict       : Enable strict mode (warnings as errors)"
  echo -e "  --html         : Generate HTML report"
  echo -e "  --no-html      : Disable HTML report"
  echo -e "  --graph        : Generate dependency graph"
  echo -e "  --output DIR   : Set output directory"
  echo -e "  --verbose      : Show detailed output"
  echo -e "  --list-checks  : List available checks"
  echo -e "  --help         : Show this help"
  exit 0
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --strict) STRICT_MODE="true"; shift ;;
      --html) HTML_REPORT="true"; shift ;;
      --no-html) HTML_REPORT="false"; shift ;;
      --graph) DEPENDENCY_GRAPH="true"; shift ;;
      --output) REPORTS_DIR="$2"; shift 2 ;;
      --verbose) VERBOSE="true"; shift ;;
      --list-checks)
        echo -e "${BOLD}Available checks:${RESET}"
        for check in "${DEFAULT_CHECKS[@]}"; do echo "  - $check"; done
        exit 0
        ;;
      --help|-h) print_help ;;
      *)
        echo -e "${FAIL_COLOR}Unknown option: $1${RESET}"
        print_help
        exit 1
        ;;
    esac
  done
}

# === DEPENDENCY GRAPH ===
generate_dependency_graph() {
  if [[ "$DEPENDENCY_GRAPH" != "true" ]]; then return; fi
  if ! command -v dot &>/dev/null; then
    record_result "warn" "Dependency" "Graphviz" "Install 'dot' to enable dependency graph"
    return
  fi

  local graph_file="$REPORTS_DIR/dependencies.dot"
  echo "digraph Dependencies {" > "$graph_file"
  echo "  node [shape=box, style=filled, color=lightblue];" >> "$graph_file"
  echo "  rankdir=LR;" >> "$graph_file"

  awk '/<dependency>/,/<\/dependency>/' "$POM_FILE" 2>/dev/null \
    | awk 'BEGIN{RS="<dependency>";FS="\n"} NR>1 {print $0}' \
    | while read -r dep; do
        group=$(echo "$dep" | grep -oP "<groupId>(.*?)</groupId>" | sed -E 's|<groupId>(.*)</groupId>|\1|' 2>/dev/null || true)
        artifact=$(echo "$dep" | grep -oP "<artifactId>(.*?)</artifactId>" | sed -E 's|<artifactId>(.*)</artifactId>|\1|' 2>/dev/null || true)
        version=$(echo "$dep" | grep -oP "<version>(.*?)</version>" | sed -E 's|<version>(.*)</version>|\1|' 2>/dev/null || true)
        if [[ -n "$group" && -n "$artifact" ]]; then
          version=${version:-$(resolve_property "$version")}
          label="$artifact\n${version:-unknown}"
          echo "  \"$group:$artifact\" [label=\"$label\"];" >> "$graph_file"
        fi
    done

  echo "}" >> "$graph_file"
  if dot -Tpng "$graph_file" -o "$REPORTS_DIR/dependencies.png" 2>/dev/null; then
    if [[ "$HTML_REPORT" == "true" ]]; then
      sed -i '/<\/div>/i <div style="margin-top:12px"><img src="dependencies.png" alt="Dependency Graph" style="max-width:100%;border-radius:8px;margin-top:10px;"></div>' "$REPORTS_DIR/pom-validation-report.html"
    fi
  fi
}

# === UI FUNCTIONS ===
print_banner() {
  local width=80
  local title="POM VALIDATOR v1.4"
  local timestamp
  timestamp=$(date +"%d-%b-%Y %I:%M %p")

  printf "${BOLD}${HEADER_BLUE}╔"
  for ((i=0;i<width-2;i++)); do printf "═"; done
  printf "╗${RESET}\n"

  printf "${BOLD}${HEADER_BLUE}║ %s %s" "$title" "$timestamp"
  local used_len=$(( ${#title} + ${#timestamp} + 2 ))
  local pad=$((width - used_len - 3))
  printf "%*s" "$pad" ""
  printf "║${RESET}\n"

  printf "${BOLD}${HEADER_BLUE}╚"
  for ((i=0;i<width-2;i++)); do printf "═"; done
  printf "╝${RESET}\n\n"

  printf "📡 ${BOLD}Initializing POM VALIDATOR ...${RESET}\n\n"
}

print_project_info() {
  # Updated: Labels in blue (INFO_COLOR), values keep their original colors
  printf "${PROJECT_ICON} ${BOLD}${INFO_COLOR}Project version: ${RESET}${VERSION_COLOR}%s${RESET}\n" "${project_version}"
  printf "${STAGE_ICON} ${BOLD}${INFO_COLOR}Project stage: ${RESET}${STAGE_COLOR}%s${RESET}\n" "${project_stage}"
  local mode_text
  mode_text=$( [[ "$STRICT_MODE" == "true" ]] && echo "STRICT" || echo "NORMAL" )
  printf "${MODE_ICON} ${BOLD}${INFO_COLOR}Validation mode: ${RESET}${MODE_COLOR}%s${RESET}\n\n" "$mode_text"
}

print_section_header() {
  local title="$1"
  local color="$2"
  printf "${BOLD}${color}"
  for ((i=0;i<80;i++)); do printf "━"; done
  printf "${RESET}\n"
  printf "${BOLD}${color}❯ %s${RESET}\n" "$title"
  printf "${BOLD}${color}"
  for ((i=0;i<80;i++)); do printf "━"; done
  printf "${RESET}\n\n"
}

print_progress_bar_from_statuses() {
  local -n statuses_ref=$1
  local total=${#statuses_ref[@]}
  local pass_count=0
  local out=""

  for s in "${statuses_ref[@]}"; do
    case "$s" in
      P) out+="$PB_PASS"; ((pass_count++)) ;;
      F) out+="$PB_FAIL" ;;
      I) out+="$PB_INFO" ;;
      W) out+="$PB_WARN" ;;
      S) out+="$PB_SKIP" ;;
      *) out+="$PB_INFO" ;;
    esac
  done

  local pct=0
  if (( total > 0 )); then
    pct=$(( pass_count * 100 / total ))
  fi

  printf "  ${BOLD}%s ${pct}%% (%d/%d checks)${RESET}\n" "$out" "$pass_count" "$total"
}

print_section() {
  local category="$1"
  local title="$2"
  local header_color="${3:-$SECTION_PURPLE}"

  print_section_header "$title" "$header_color"

  # Read results
  local results=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && results+=("$line")
  done < <(echo -e "${CATEGORY_RESULTS[$category]}")

  if [[ ${#results[@]} -eq 0 ]]; then
    printf "  ${SKIP_COLOR}${SKIP_ICON} No checks performed for this category.${RESET}\n\n"
    return
  fi

  # Compute max item width
  local max_item_len=0
  for result in "${results[@]}"; do
    IFS='|' read -r status item message <<< "$result"
    local l
    l=$(get_display_width "$item")
    (( l > max_item_len )) && max_item_len=$l
  done

  # cap max width for sanity
  (( max_item_len > 30 )) && max_item_len=30

  # Collect section statuses
  local section_statuses=()

  # Print aligned results
  for result in "${results[@]}"; do
    IFS='|' read -r status item message <<< "$result"
    local item_short="$item"
    # Truncate long item names
    if (( $(get_display_width "$item_short") > max_item_len )); then
      item_short="${item_short:0:$((max_item_len-3))}..."
    fi
    local padding=$(( max_item_len - $(get_display_width "$item_short") ))
    local pad_str=""
    for ((i=0;i<padding;i++)); do pad_str+=" "; done

    case "$status" in
      pass) printf "  ${PASS_COLOR}✔ ${item_short}${pad_str} → ${PASS_ICON} ${ARROW_ICON} ${message}${RESET}\n" ;;
      warn) printf "  ${WARN_COLOR}⚠ ${item_short}${pad_str} → ${WARN_ICON} ${ARROW_ICON} ${message}${RESET}\n" ;;
      fail) printf "  ${FAIL_COLOR}✗ ${item_short}${pad_str} → ${FAIL_ICON} ${ARROW_ICON} ${message}${RESET}\n" ;;
      info) printf "  ${INFO_COLOR}ℹ ${item_short}${pad_str} → ${INFO_ICON} ${ARROW_ICON} ${message}${RESET}\n" ;;
      skip) printf "  ${SKIP_COLOR}↷ ${item_short}${pad_str} → ${SKIP_ICON} ${ARROW_ICON} ${message}${RESET}\n" ;;
      *) printf "  ${INFO_COLOR}ℹ ${item_short}${pad_str} → ${INFO_ICON} ${ARROW_ICON} ${message}${RESET}\n" ;;
    esac

    case "$status" in
      pass) section_statuses+=("P") ;;
      warn) section_statuses+=("W") ;;
      fail) section_statuses+=("F") ;;
      info) section_statuses+=("I") ;;
      skip) section_statuses+=("S") ;;
      *) section_statuses+=("I") ;;
    esac
  done

  printf "\n"
  print_progress_bar_from_statuses section_statuses

  # Section counts
  declare -A section_counts=( [pass]=0 [warn]=0 [fail]=0 [info]=0 [skip]=0 )
  for s in "${section_statuses[@]}"; do
    case "$s" in
      P) ((section_counts[pass]++)) ;;
      W) ((section_counts[warn]++)) ;;
      F) ((section_counts[fail]++)) ;;
      I) ((section_counts[info]++)) ;;
      S) ((section_counts[skip]++)) ;;
    esac
  done

  # Updated: Entire status blocks in their respective colors
  printf "  ${BOLD}${PASS_COLOR}✔ Passed 🟢 ${ARROW_ICON} %d${RESET} | " "${section_counts["pass"]}"
  printf "${BOLD}${WARN_COLOR}⚠ Warnings 🟠 ${ARROW_ICON} %d${RESET} | " "${section_counts["warn"]}"
  printf "${BOLD}${FAIL_COLOR}✗ Failures 🔴 ${ARROW_ICON} %d${RESET} | " "${section_counts["fail"]}"
  printf "${BOLD}${INFO_COLOR}ℹ Info 🔵 ${ARROW_ICON} %d${RESET} | " "${section_counts["info"]}"
  printf "${BOLD}${SKIP_COLOR}↷ Skipped ⚫ ${ARROW_ICON} %d${RESET}\n\n" "${section_counts["skip"]}"
}

print_final_summary() {
  local header_color="${1:-$SECTION_PURPLE}"
  printf "${BOLD}${header_color}"
  for ((i=0;i<80;i++)); do printf "━"; done
  printf "${RESET}\n"
  printf "${BOLD}${header_color}❯ FINAL SUMMARY${RESET}\n"
  printf "${BOLD}${header_color}"
  for ((i=0;i<80;i++)); do printf "━"; done
  printf "${RESET}\n\n"

  # Overall progress bar
  local total=${#CHECK_STATUS_ARRAY[@]}
  local pass_count=0
  local out=""
  for s in "${CHECK_STATUS_ARRAY[@]}"; do
    case "$s" in
      P) out+="$PB_PASS"; ((pass_count++)) ;;
      W) out+="$PB_WARN" ;;
      F) out+="$PB_FAIL" ;;
      I) out+="$PB_INFO" ;;
      S) out+="$PB_SKIP" ;;
      *) out+="$PB_INFO" ;;
    esac
  done
  local pct=0
  if (( total>0 )); then pct=$(( pass_count*100/total )); fi
  printf "  ${BOLD}%s ${pct}%% (%d/%d checks)${RESET}\n\n" "$out" "$pass_count" "$total"

  # Summary counts
  local p=${counts["pass"]}; local w=${counts["warn"]}; local f=${counts["fail"]}; local i=${counts["info"]}; local s=${counts["skip"]}
  printf "  ${BOLD}${TOTAL_COLOR}🔥 Total Checks 💯 ${ARROW_ICON} %d checks processed${RESET}\n" "$total"
  # Updated: Entire status blocks in their respective colors
  printf "  ${BOLD}${PASS_COLOR}✔ Passed 🟢 ${ARROW_ICON} %d${RESET} | " "$p"
  printf "${BOLD}${WARN_COLOR}⚠ Warnings 🟠 ${ARROW_ICON} %d${RESET} | " "$w"
  printf "${BOLD}${FAIL_COLOR}✗ Failures 🔴 ${ARROW_ICON} %d${RESET} | " "$f"
  printf "${BOLD}${INFO_COLOR}ℹ Info 🔵 ${ARROW_ICON} %d${RESET} | " "$i"
  printf "${BOLD}${SKIP_COLOR}↷ Skipped ⚫ ${ARROW_ICON} %d${RESET}\n\n" "$s"

  # Result message
  if [[ ${counts["fail"]} -eq 0 && (${counts["warn"]} -eq 0 || "$STRICT_MODE" != "true") ]]; then
    printf "  ${BOLD}${PASS_COLOR}🎉 POM validation completed successfully${RESET}\n\n"
  else
    printf "  ${BOLD}${FAIL_COLOR}❌ POM validation completed with issues${RESET}\n\n"
  fi

  # Author section (CLI)
  echo -e "${AUTHOR_BG}${AUTHOR_FG} ${BOLD}${AUTHOR_NAME_COLOR}${AUTHOR_NAME} 🏅 ${RESET}${AUTHOR_BG}${AUTHOR_FG} ${BOLD}${AUTHOR_ROLE_COLOR}${AUTHOR_ROLE}${RESET}"
  echo -e "${AUTHOR_BG}${AUTHOR_FG}  📧 ${AUTHOR_EMAIL_COLOR}${AUTHOR_EMAIL}${RESET}${AUTHOR_BG}${AUTHOR_FG}  |  🔗 ${AUTHOR_LINK_COLOR}${AUTHOR_LINKEDIN} ${RESET}\n"

  printf "  ${BOLD}${THANKS_COLOR}💫 Thank you for using POM VALIDATOR.${RESET}\n\n"
  printf "  Completed at: $(date +"%d-%b-%Y %I:%M:%S %p")\n"
}

# === CHECK FUNCTIONS ===
check_project_info() {
  for item in "${!PROJECT_INFO_REQUIREMENTS[@]}"; do
    local required_version="${PROJECT_INFO_REQUIREMENTS["$item"]}"
    if ! version_ge "$project_version" "$required_version"; then
      local milestone_name="${MILESTONE_MAP["$required_version"]:-$required_version}"
      local friendly
      friendly=$(echo "$milestone_name" | sed 's/[^ ]* /\L&/g')
      record_result "skip" "Project Information" "$item" "Planned for $friendly in $required_version."
      continue
    fi

    case "$item" in
      groupId|artifactId|version|modelVersion)
        local val
        val=$(get_tag_value "$item")
        if [[ -z "$val" ]]; then
          record_result "fail" "Project Information" "$item" "Required field missing"
        else
          record_result "pass" "Project Information" "$item" "$val"
        fi
        ;;
      encoding)
        local val
        val=$(get_tag_value "project.build.sourceEncoding")
        if [[ "$val" == "UTF-8" ]]; then
          record_result "pass" "Project Information" "Encoding" "UTF-8"
        else
          if [[ -z "$val" ]]; then
            record_result "warn" "Project Information" "Encoding" "Not specified (recommend UTF-8)"
          else
            record_result "warn" "Project Information" "Encoding" "Found '$val' (recommend UTF-8)"
          fi
        fi
        ;;
      java)
        local java_version required_java
        java_version=$(get_tag_value "java.version")
        required_java="${VERSION_REQUIREMENTS["java.version"]}"
        if [[ -n "$java_version" ]]; then
          if version_ge "$java_version" "$required_java"; then
            record_result "pass" "Project Information" "Java" "$java_version >= $required_java"
          else
            record_result "fail" "Project Information" "Java" "$java_version < $required_java"
          fi
        else
          record_result "warn" "Project Information" "Java" "Not specified"
        fi
        ;;
      *)
        record_result "info" "Project Information" "$item" "No rule defined"
        ;;
    esac
  done
}

check_dependencies() {
  for dep in "${!DEPENDENCY_REQUIREMENTS[@]}"; do
    local required_version="${DEPENDENCY_REQUIREMENTS["$dep"]}"
    local min_version="${VERSION_REQUIREMENTS["$dep"]}"
    local milestone_name="${MILESTONE_MAP["$required_version"]:-$required_version}"

    if ! version_ge "$project_version" "$required_version"; then
      local friendly
      friendly=$(echo "$milestone_name" | sed 's/[^ ]* /\L&/g')
      record_result "skip" "Dependencies" "$dep" "Planned for $friendly in $required_version."
      continue
    fi

    local version resolved_version
    version=$(get_version_by_artifact_id "$dep")
    resolved_version=$(resolve_property "$version")

    if [[ -n "$resolved_version" ]]; then
      if version_ge "$resolved_version" "$min_version"; then
        record_result "pass" "Dependencies" "$dep" "$resolved_version >= $min_version"
      else
        record_result "fail" "Dependencies" "$dep" "$resolved_version < $min_version"
      fi
    else
      record_result "fail" "Dependencies" "$dep" "Missing"
    fi
  done
}

check_plugins() {
  for plugin in "${!PLUGIN_REQUIREMENTS[@]}"; do
    local required_version="${PLUGIN_REQUIREMENTS["$plugin"]}"
    local min_version="${VERSION_REQUIREMENTS["$plugin"]}"
    local milestone_name="${MILESTONE_MAP["$required_version"]:-$required_version}"

    if ! version_ge "$project_version" "$required_version"; then
      local friendly
      friendly=$(echo "$milestone_name" | sed 's/[^ ]* /\L&/g')
      record_result "skip" "Plugins" "$plugin" "Planned for $friendly in $required_version."
      continue
    fi

    local version resolved_version
    version=$(get_version_by_artifact_id "$plugin")
    resolved_version=$(resolve_property "$version")

    if [[ -n "$resolved_version" ]]; then
      if version_ge "$resolved_version" "$min_version"; then
        record_result "pass" "Plugins" "$plugin" "$resolved_version >= $min_version"
      else
        record_result "fail" "Plugins" "$plugin" "$resolved_version < $min_version"
      fi
    else
      record_result "warn" "Plugins" "$plugin" "Not configured"
    fi
  done
}

# === MAIN ===
main() {
  parse_arguments "$@"

  if [[ ! -f "$POM_FILE" ]]; then
    echo -e "${FAIL_COLOR}${BOLD}✗ Error: POM file not found: $POM_FILE${RESET}"
    exit 1
  fi

  validate_xml

  # Get project version
  project_version="v$(get_tag_value version)"
  [[ -z "$project_version" || "$project_version" == "v" ]] && project_version="v0.0.0"
  project_stage="${MILESTONE_MAP["$project_version"]:-Unknown}"

  init_output_dir
  print_banner
  print_project_info

  # Count total checks (only those gated by project version)
  total_checks=0
  for item in "${!PROJECT_INFO_REQUIREMENTS[@]}"; do
    version_ge "$project_version" "${PROJECT_INFO_REQUIREMENTS["$item"]}" && ((total_checks++))
  done
  for dep in "${!DEPENDENCY_REQUIREMENTS[@]}"; do
    version_ge "$project_version" "${DEPENDENCY_REQUIREMENTS["$dep"]}" && ((total_checks++))
  done
  for plugin in "${!PLUGIN_REQUIREMENTS[@]}"; do
    version_ge "$project_version" "${PLUGIN_REQUIREMENTS["$plugin"]}" && ((total_checks++))
  done

  # Execute checks
  "${CHECK_FUNCS["project_info"]}"
  "${CHECK_FUNCS["dependencies"]}"
  "${CHECK_FUNCS["plugins"]}"

  # Print results
  print_section "Project Information" "✍ PROJECT INFORMATION" "$SECTION_PURPLE"
  print_section "Dependencies" "🏗 DEPENDENCIES" "$SECTION_CYAN"
  print_section "Plugins" "🔌 PLUGINS" "$SECTION_BLUE"

  # Generate dependency graph if requested
  generate_dependency_graph

  # Finalize HTML and print summary
  finalize_html_report
  print_final_summary "$SECTION_PURPLE"

  # Exit status
  fail_count=${counts["fail"]}
  warn_count=${counts["warn"]}
  if [[ "$STRICT_MODE" == "true" && $((fail_count + warn_count)) -gt 0 ]]; then
    exit 1
  elif [[ $fail_count -gt 0 ]]; then
    exit 1
  else
    exit 0
  fi
}

main "$@"
