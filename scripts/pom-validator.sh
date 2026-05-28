#!/usr/bin/env bash
# Ultimate POM Validator v2.4 - Dynamic Section Status Edition

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
PASS_COLOR='\033[1;38;5;46m'    # bright green
WARN_COLOR='\033[1;38;5;208m'   # orange
FAIL_COLOR='\033[1;38;5;196m'   # red
INFO_COLOR='\033[1;38;5;33m'    # blue
SKIP_COLOR='\033[1;38;5;240m'   # grey/blackish
VERSION_COLOR='\033[1;38;5;93m'    # purple
STAGE_COLOR='\033[1;38;5;220m'     # yellow
MODE_COLOR='\033[1;38;5;45m'       # teal
SECTION_PURPLE='\033[1;38;5;141m'   # brighter magenta
SECTION_CYAN='\033[1;38;5;51m'      # vibrant cyan
SECTION_BLUE='\033[1;38;5;75m'      # ocean blue
HEADER_BLUE='\033[1;38;5;39m'       # header blue
TOTAL_COLOR='\033[1;38;5;117m'      # light blue
THANKS_COLOR='\033[1;38;5;219m'     # pink

# === ICONS & BLOCKS ===
PASS_ICON="🟢"; WARN_ICON="🟠"; FAIL_ICON="🔴"; INFO_ICON="🔵"; SKIP_ICON="⚫"; ARROW_ICON="⇒"
PROJECT_ICON="📜"; STAGE_ICON="📸"; MODE_ICON="⚔️"
PB_PASS="🟩"; PB_FAIL="🟥"; PB_INFO="🟦"; PB_WARN="🟧"; PB_SKIP="⬛"

# Author info
AUTHOR_NAME="ANUJ KUMAR"
AUTHOR_ROLE="QA Lead & AI-Assisted Testing Specialist"
AUTHOR_EMAIL="anujpatiyal@live.in"
AUTHOR_LINKEDIN="https://www.linkedin.com/in/anuj-kumar-qa/"

# === MILESTONE MAP ===
declare -A MILESTONE_MAP=(
  ["v0.0.0"]="Project Skeleton & CI Setup"
  ["v0.1.0"]="Playwright Core & First Test"
  ["v0.2.0"]="Logging & Advanced Utilities"
  ["v0.3.0"]="Page Object Model Architecture"
  ["v0.4.0"]="Data Driven Setup"
  ["v0.5.0"]="Allure Reporting Integration"
  ["v1.0.0"]="Stable Master Release"
)

# === VERSION REQUIREMENTS ===
declare -A VERSION_REQUIREMENTS=(
  ["playwright"]="1.50.0"
  ["testng"]="7.0.0"
  ["log4j-core"]="2.0.0"
  ["log4j-api"]="2.0.0"
  ["allure-testng"]="2.0.0"
  ["maven-surefire-plugin"]="3.0.0"
  ["maven-compiler-plugin"]="3.0.0"
  ["maven-clean-plugin"]="3.0.0"
  ["java.version"]="17"
)

declare -A PROJECT_INFO_REQUIREMENTS=( ["groupId"]="v0.0.0" ["artifactId"]="v0.0.0" ["version"]="v0.0.0" ["name"]="v0.0.0" ["java"]="v0.0.0" )
declare -A DEPENDENCY_REQUIREMENTS=( ["playwright"]="v0.1.0" ["testng"]="v0.1.0" ["log4j-core"]="v0.2.0" ["log4j-api"]="v0.2.0" ["allure-testng"]="v0.5.0" )
declare -A PLUGIN_REQUIREMENTS=( ["maven-compiler-plugin"]="v0.1.0" ["maven-surefire-plugin"]="v0.1.0" ["maven-clean-plugin"]="v0.1.0" )

# === TRACKING ===
declare -A counts=( ["pass"]=0 ["warn"]=0 ["fail"]=0 ["info"]=0 ["skip"]=0 )
declare -a ALL_RESULTS=()
declare -a CHECK_STATUS_ARRAY=()
declare -A CATEGORY_RESULTS=( ["Project Information"]="" ["Dependencies"]="" ["Plugins"]="" )
declare -g IS_SNAPSHOT=false

# === UTILITY FUNCTIONS ===
get_display_width() { echo -n "$1" | wc -m; }

validate_xml() {
  if ! command -v xmllint &>/dev/null; then echo -e "${WARN_COLOR}${BOLD}⚠ xmllint not found; skipping strict XML validation${RESET}"; return 0; fi
  if ! xmllint --noout "$POM_FILE" 2>/dev/null; then echo -e "${FAIL_COLOR}${BOLD}✗ Error: Invalid XML in $POM_FILE${RESET}"; exit 1; fi
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
<title>Playwright Framework POM Report</title>
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&family=Poppins:wght@400;600;800&display=swap" rel="stylesheet">
<style>
:root{ --bg-main: #050510; --bg-card: rgba(16, 20, 35, 0.45); --text-main: #e2e8f0; --text-muted: #8b9bb4; --neon-cyan: #00f0ff; --neon-magenta: #ff003c; --neon-purple: #b026ff; --neon-green: #00ff66; --neon-orange: #ffaa00; --neon-blue: #0066ff; --neon-gray: #7a8a9e; --glass-border: 1px solid rgba(255, 255, 255, 0.08); }
* { box-sizing: border-box; }
body { margin: 0; background: radial-gradient(circle at top right, #0d0c1c, var(--bg-main) 60%); color: var(--text-main); font-family: 'Poppins', sans-serif; min-height: 100vh; }
.container { max-width: 1150px; margin: 30px auto; padding: 20px; }
.header { display: flex; align-items: center; justify-content: space-between; gap: 15px; margin-bottom: 25px; }
.header-left h1 { margin: 0; font-weight: 800; font-size: 26px; background: linear-gradient(90deg, var(--neon-cyan), var(--neon-purple)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; text-shadow: 0px 0px 20px rgba(0, 240, 255, 0.3); }
.meta { color: var(--text-muted); font-size: 13px; margin-top: 5px; font-family: 'JetBrains Mono', monospace;}
.badge-header { padding: 8px 14px; border-radius: 8px; font-weight: 600; font-size: 13px; background: rgba(0, 240, 255, 0.05); color: var(--neon-cyan); border: 1px solid rgba(0, 240, 255, 0.2); display: inline-flex; align-items: center; gap: 8px; box-shadow: 0 0 10px rgba(0,240,255,0.1); }
.card { background: var(--bg-card); backdrop-filter: blur(16px); -webkit-backdrop-filter: blur(16px); border-radius: 16px; padding: 25px; border: var(--glass-border); box-shadow: 0 8px 32px 0 rgba(0,0,0,0.37); }
.section-title { display: flex; align-items: center; gap: 10px; font-weight: 800; font-size: 18px; text-transform: uppercase; letter-spacing: 1px; padding: 12px 20px; border-radius: 10px; color: #fff; background: linear-gradient(90deg, rgba(176,38,255,0.2), rgba(0,240,255,0.05)); border-left: 4px solid var(--neon-cyan); margin-bottom: 20px; box-shadow: inset 0 0 20px rgba(0,240,255,0.05); }
.grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
@media(max-width:900px){ .grid { grid-template-columns: 1fr; } }
.table-container { margin-bottom: 20px; }
.table-label { font-weight: 600; color: #fff; margin-bottom: 12px; font-size: 15px; display: inline-block; border-bottom: 2px solid var(--neon-purple); padding-bottom: 4px; text-shadow: 0 0 10px rgba(176,38,255,0.3); }
.table { width: 100%; border-collapse: separate; border-spacing: 0; table-layout: fixed; }
.table th { background: rgba(255,255,255,0.03); padding: 14px; text-align: left; color: var(--text-muted); font-size: 12px; text-transform: uppercase; letter-spacing: 1px; border-bottom: var(--glass-border); border-top-left-radius: 8px; border-top-right-radius: 8px;}
.table td { padding: 12px 14px; font-size: 13px; border-bottom: 1px solid rgba(255,255,255,0.02); font-family: 'JetBrains Mono', monospace; word-wrap: break-word; transition: all 0.2s ease; }
.table tr:hover td { background: rgba(255,255,255,0.08); }
.tr-pass td:first-child { border-left: 3px solid var(--neon-green); }
.tr-warn td:first-child { border-left: 3px solid var(--neon-orange); }
.tr-fail td:first-child { border-left: 3px solid var(--neon-magenta); }
.tr-info td:first-child { border-left: 3px solid var(--neon-blue); }
.tr-skip td:first-child { border-left: 3px solid var(--neon-gray); }
/* Colored Text Classes */
.text-pass { color: var(--neon-green); font-weight: bold; text-shadow: 0 0 5px rgba(0,255,102,0.3); }
.text-warn { color: var(--neon-orange); font-weight: bold; text-shadow: 0 0 5px rgba(255,170,0,0.3); }
.text-fail { color: var(--neon-magenta); font-weight: bold; text-shadow: 0 0 5px rgba(255,0,60,0.3); }
.text-info { color: var(--neon-blue); font-weight: bold; }
.text-skip { color: var(--text-muted); font-weight: normal; }

.status-badge { display: inline-flex; align-items: center; justify-content: center; gap: 6px; padding: 4px 10px; border-radius: 6px; font-weight: 700; font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; font-family: 'Poppins', sans-serif; min-width: 80px; }
.badge-pass { background: rgba(0,255,102,0.1); color: var(--neon-green); border: 1px solid rgba(0,255,102,0.3); box-shadow: 0 0 10px rgba(0,255,102,0.15); }
.badge-warn { background: rgba(255,170,0,0.1); color: var(--neon-orange); border: 1px solid rgba(255,170,0,0.3); box-shadow: 0 0 10px rgba(255,170,0,0.15); }
.badge-fail { background: rgba(255,0,60,0.1); color: var(--neon-magenta); border: 1px solid rgba(255,0,60,0.3); box-shadow: 0 0 10px rgba(255,0,60,0.2); }
.badge-info { background: rgba(0,102,255,0.1); color: var(--neon-blue); border: 1px solid rgba(0,102,255,0.3); box-shadow: 0 0 10px rgba(0,102,255,0.2); }
.badge-skip { background: rgba(122,138,158,0.1); color: var(--neon-gray); border: 1px solid rgba(122,138,158,0.3); }

/* Progress Bar Design */
.progress-container { margin-top: 25px; padding: 15px; background: rgba(0,0,0,0.2); border-radius: 12px; border: var(--glass-border); }
.progress-label { font-size: 12px; text-transform: uppercase; letter-spacing: 1px; color: var(--text-muted); margin-bottom: 10px; display: block; font-weight: 600; }
.progress-strip { display: flex; height: 14px; border-radius: 8px; overflow: hidden; background: rgba(0,0,0,0.4); box-shadow: inset 0 2px 4px rgba(0,0,0,0.5); }
.pb-segment { height: 100%; transition: width 0.4s ease; border-right: 1px solid rgba(0,0,0,0.3); }
.pb-segment:last-child { border-right: none; }
.pb-pass { background: linear-gradient(90deg, #00b34d, var(--neon-green)); box-shadow: 0 0 10px rgba(0,255,102,0.4); }
.pb-warn { background: linear-gradient(90deg, #cc8800, var(--neon-orange)); box-shadow: 0 0 10px rgba(255,170,0,0.4); }
.pb-fail { background: linear-gradient(90deg, #b3002a, var(--neon-magenta)); box-shadow: 0 0 10px rgba(255,0,60,0.4); }
.pb-info { background: linear-gradient(90deg, #004de6, var(--neon-blue)); box-shadow: 0 0 10px rgba(0,102,255,0.4); }
.pb-skip { background: linear-gradient(90deg, #4a5a6e, var(--neon-gray)); }

.summary-grid { display: grid; grid-template-columns: repeat(5, 1fr); gap: 15px; margin-top: 25px; }
.summary-card { padding: 20px; border-radius: 12px; text-align: center; border: var(--glass-border); background: rgba(255,255,255,0.02); transition: transform 0.2s ease, box-shadow 0.2s ease; position: relative; overflow: hidden; }
.summary-card:hover { transform: translateY(-3px); background: rgba(255,255,255,0.04); }
.summary-card .big { font-size: 28px; font-weight: 800; font-family: 'JetBrains Mono', monospace; margin-top: 8px; }
.summary-pass { border-bottom: 4px solid var(--neon-green); background: linear-gradient(180deg, rgba(0,255,102,0.05), transparent); }
.summary-pass .big { color: var(--neon-green); text-shadow: 0 0 10px rgba(0,255,102,0.4); }
.summary-warn { border-bottom: 4px solid var(--neon-orange); background: linear-gradient(180deg, rgba(255,170,0,0.05), transparent); }
.summary-warn .big { color: var(--neon-orange); text-shadow: 0 0 10px rgba(255,170,0,0.4); }
.summary-fail { border-bottom: 4px solid var(--neon-magenta); background: linear-gradient(180deg, rgba(255,0,60,0.05), transparent); }
.summary-fail .big { color: var(--neon-magenta); text-shadow: 0 0 10px rgba(255,0,60,0.4); }
.summary-info { border-bottom: 4px solid var(--neon-blue); background: linear-gradient(180deg, rgba(0,102,255,0.05), transparent); }
.summary-info .big { color: var(--neon-blue); text-shadow: 0 0 10px rgba(0,102,255,0.4); }
.summary-skip { border-bottom: 4px solid var(--neon-gray); background: linear-gradient(180deg, rgba(122,138,158,0.05), transparent); }
.summary-skip .big { color: var(--neon-gray); }
.author-card { background: rgba(16, 20, 35, 0.6); backdrop-filter: blur(16px); padding: 20px 25px; border-radius: 16px; margin-top: 25px; display: flex; gap: 20px; align-items: center; border: 1px solid rgba(176,38,255,0.2); box-shadow: 0 10px 30px rgba(176,38,255,0.1); }
.author-card .avatar { width: 60px; height: 60px; border-radius: 12px; background: linear-gradient(135deg, var(--neon-cyan), var(--neon-purple)); display: flex; align-items: center; justify-content: center; font-weight: 800; color: #fff; font-size: 22px; box-shadow: 0 0 20px rgba(0,240,255,0.4); }
.author-name { font-weight: 800; font-size: 18px; color: #fff; text-shadow: 0 0 10px rgba(255,255,255,0.2); }
.author-role { font-weight: 600; font-size: 13px; color: var(--neon-orange); margin-top: 4px; }
.author-links { font-size: 13px; margin-top: 10px; color: var(--text-muted); font-family: 'JetBrains Mono', monospace;}
.author-links a { color: var(--neon-cyan); text-decoration: none; transition: 0.2s; }
.author-links a:hover { text-shadow: 0 0 8px var(--neon-cyan); }
.footer { margin-top: 25px; color: var(--text-muted); font-size: 12px; text-align: right; font-family: 'JetBrains Mono', monospace; }
</style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="header-left">
        <h1>Playwright POM Report</h1>
        <div class="meta">Executed on $(date +"%d %b %Y | %H:%M:%S")</div>
      </div>
      <div class="header-right">
        <div class="badge-header">🎯 Stage: ${MILESTONE_MAP["$project_version"]:-"Unknown"}</div>
        <div class="badge-header" style="border-color: rgba(176,38,255,0.3); color: #fff; background: rgba(176,38,255,0.1);">🚀 v${project_version#v}</div>
      </div>
    </div>
    <div class="card">
      <div class="section-title">✨ Validation Summary Matrix</div>
      <div class="grid">
        <div class="table-container">
          <div class="table-label">✍ Project Information</div>
          <table class="table"><thead><tr><th style="width:35%">Definition</th><th style="width:20%">Status</th><th style="width:45%">Result</th></tr></thead>
            <tbody id="report-body-project"></tbody>
          </table>
        </div>
        <div class="table-container">
          <div class="table-label">🏗 Dependencies</div>
          <table class="table"><thead><tr><th style="width:35%">Artifact</th><th style="width:20%">Status</th><th style="width:45%">Version Check</th></tr></thead>
            <tbody id="report-body-deps"></tbody>
          </table>
        </div>
      </div>
      <div class="table-container" style="margin-top: 10px;">
        <div class="table-label">🔌 Maven Plugins</div>
        <table class="table"><thead><tr><th style="width:25%">Plugin</th><th style="width:15%">Status</th><th style="width:60%">Version Check</th></tr></thead>
          <tbody id="report-body-plugins"></tbody>
        </table>
      </div>
      <div class="summary-grid" id="summary-grid">
        <div class="summary-card summary-pass"><div style="font-size:12px; font-weight:700; text-transform:uppercase; color:#8b9bb4;">Passed</div><div class="big" id="html-pass-count">0</div></div>
        <div class="summary-card summary-warn"><div style="font-size:12px; font-weight:700; text-transform:uppercase; color:#8b9bb4;">Warnings</div><div class="big" id="html-warn-count">0</div></div>
        <div class="summary-card summary-fail"><div style="font-size:12px; font-weight:700; text-transform:uppercase; color:#8b9bb4;">Failures</div><div class="big" id="html-fail-count">0</div></div>
        <div class="summary-card summary-info"><div style="font-size:12px; font-weight:700; text-transform:uppercase; color:#8b9bb4;">Insights</div><div class="big" id="html-info-count">0</div></div>
        <div class="summary-card summary-skip"><div style="font-size:12px; font-weight:700; text-transform:uppercase; color:#8b9bb4;">Skipped</div><div class="big" id="html-skip-count">0</div></div>
      </div>
      <div class="progress-container">
        <span class="progress-label">Validation Distribution Map</span>
        <div id="html-progress-strip" class="progress-strip"></div>
      </div>
    </div>
    <div class="author-card">
      <div class="avatar">AK</div>
      <div>
        <div class="author-name">${AUTHOR_NAME}</div>
        <div class="author-role">${AUTHOR_ROLE}</div>
        <div class="author-links">📧 <a href="mailto:${AUTHOR_EMAIL}">${AUTHOR_EMAIL}</a> &nbsp;|&nbsp; 🔗 <a href="${AUTHOR_LINKEDIN}" target="_blank">LinkedIn Profile</a></div>
      </div>
    </div>
    <div class="footer">Validation Engine v2.4 • Playwright Hybrid Framework</div>
  </div>
</body>
</html>
HTML
  fi
}

finalize_html_report() {
  if [[ "$HTML_REPORT" == "true" ]]; then
    local tmp_file="$REPORTS_DIR/report_tmp.html"
    local report_file="$REPORTS_DIR/pom-validation-report.html"

    # Build the dynamic CSS flex segments based on exact status ratios
    local total=${#CHECK_STATUS_ARRAY[@]}
    local progress_html=""
    [[ $total -eq 0 ]] && total=1 # Prevent div by zero
    
    # Calculate percentage widths for segments
    local p_wid=$(awk "BEGIN {print (${counts["pass"]}/$total)*100}")
    local w_wid=$(awk "BEGIN {print (${counts["warn"]}/$total)*100}")
    local f_wid=$(awk "BEGIN {print (${counts["fail"]}/$total)*100}")
    local i_wid=$(awk "BEGIN {print (${counts["info"]}/$total)*100}")
    local s_wid=$(awk "BEGIN {print (${counts["skip"]}/$total)*100}")

    [[ ${counts["pass"]} -gt 0 ]] && progress_html+="<div class=\"pb-segment pb-pass\" style=\"width: ${p_wid}%\"></div>"
    [[ ${counts["warn"]} -gt 0 ]] && progress_html+="<div class=\"pb-segment pb-warn\" style=\"width: ${w_wid}%\"></div>"
    [[ ${counts["fail"]} -gt 0 ]] && progress_html+="<div class=\"pb-segment pb-fail\" style=\"width: ${f_wid}%\"></div>"
    [[ ${counts["info"]} -gt 0 ]] && progress_html+="<div class=\"pb-segment pb-info\" style=\"width: ${i_wid}%\"></div>"
    [[ ${counts["skip"]} -gt 0 ]] && progress_html+="<div class=\"pb-segment pb-skip\" style=\"width: ${s_wid}%\"></div>"

    # Cross-platform safe substitution
    sed -E \
      -e "s/(id=\"html-pass-count\">)[0-9]+/\1${counts["pass"]}/" \
      -e "s/(id=\"html-warn-count\">)[0-9]+/\1${counts["warn"]}/" \
      -e "s/(id=\"html-fail-count\">)[0-9]+/\1${counts["fail"]}/" \
      -e "s/(id=\"html-info-count\">)[0-9]+/\1${counts["info"]}/" \
      -e "s/(id=\"html-skip-count\">)[0-9]+/\1${counts["skip"]}/" \
      -e "s|<div id=\"html-progress-strip\" class=\"progress-strip\"></div>|<div id=\"html-progress-strip\" class=\"progress-strip\">$progress_html</div>|" \
      "$report_file" > "$tmp_file" && mv "$tmp_file" "$report_file"
  fi
}

get_version_by_artifact_id() { awk "/<artifactId>$1<\/artifactId>/,/<\/(plugin|dependency)>/" "$POM_FILE" 2>/dev/null | grep -oP "<version>(.*?)</version>" 2>/dev/null | sed -E 's|<version>(.*)</version>|\1|' 2>/dev/null | head -n1 || true; }
resolve_property() { if [[ "$1" =~ ^\$\{(.+)\}$ ]]; then get_tag_value "${BASH_REMATCH[1]}"; else echo "$1"; fi; }
get_tag_value() { grep -oP "<$1>(.*?)</$1>" "$POM_FILE" 2>/dev/null | sed -E "s|.*<$1>(.*)</$1>.*|\1|" | head -n1 || true; }
version_ge() { [ "$1" = "$2" ] && return 0; [ "$(printf "%s\n%s" "$1" "$2" | sort -V | head -n1)" = "$2" ]; }

record_result() {
  local status="$1"; local category="$2"; local item="$3"; local message="$4"
  ((counts["$status"]++))

  case "$status" in pass) CHECK_STATUS_ARRAY+=("P") ;; warn) CHECK_STATUS_ARRAY+=("W") ;; fail) CHECK_STATUS_ARRAY+=("F") ;; info) CHECK_STATUS_ARRAY+=("I") ;; skip) CHECK_STATUS_ARRAY+=("S") ;; *) CHECK_STATUS_ARRAY+=("I") ;; esac

  local clean_message=$(echo -e "$message" | sed -E "s/\\\033\[[0-9;]*m//g")
  CATEGORY_RESULTS["$category"]+="$status|$item|$clean_message\n"

  if [[ "$HTML_REPORT" == "true" ]]; then
    local tid html_icon
    case "$category" in "Project Information") tid="report-body-project" ;; "Dependencies") tid="report-body-deps" ;; "Plugins") tid="report-body-plugins" ;; *) tid="report-body-project" ;; esac
    case "$status" in pass) html_icon="🟢" ;; warn) html_icon="🟠" ;; fail) html_icon="🔴" ;; info) html_icon="🔵" ;; skip) html_icon="⚫" ;; *) html_icon="ℹ" ;; esac

    local badge_class="badge-$status"
    local row_class="tr-$status"
    local text_class="text-$status"
    
    # Use tmp file for safe injection
    local tmp_file="$REPORTS_DIR/report_tmp.html"
    local report_file="$REPORTS_DIR/pom-validation-report.html"
    
    sed -e "/id=\"$tid\"/a\\
    <tr class=\"$row_class\"><td><strong>$item</strong></td><td><span class=\"status-badge $badge_class\">$html_icon ${status}</span></td><td class=\"$text_class\">${clean_message}</td></tr>" \
    "$report_file" > "$tmp_file" && mv "$tmp_file" "$report_file"
  fi
}

print_banner() { 
  printf "${BOLD}${HEADER_BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}\n"
  printf "${BOLD}${HEADER_BLUE}║ POM VALIDATOR v2.4 - Playwright Framework (Snapshot Safe)                    ║${RESET}\n"
  printf "${BOLD}${HEADER_BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}\n\n"
}

print_project_info() { 
  printf "${PROJECT_ICON} ${BOLD}${INFO_COLOR}Project version: ${RESET}${VERSION_COLOR}%s${RESET}\n" "${project_version}"
  printf "${STAGE_ICON} ${BOLD}${INFO_COLOR}Project stage: ${RESET}${STAGE_COLOR}%s${RESET}\n" "${project_stage}"
  printf "${MODE_ICON} ${BOLD}${INFO_COLOR}Validation mode: ${RESET}${MODE_COLOR}%s${RESET}\n\n" "$([[ "$STRICT_MODE" == "true" ]] && echo "STRICT" || echo "NORMAL")"
}

print_section_header() { 
  printf "${BOLD}$2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
  printf "${BOLD}$2❯ $1${RESET}\n"
  printf "${BOLD}$2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n\n"
}

print_section() {
  local category="$1"; local title="$2"; local header_color="${3:-$SECTION_PURPLE}"
  print_section_header "$title" "$header_color"
  local results=(); while IFS= read -r line; do [[ -n "$line" ]] && results+=("$line"); done < <(echo -e "${CATEGORY_RESULTS[$category]}")
  if [[ ${#results[@]} -eq 0 ]]; then printf "  ${SKIP_COLOR}${SKIP_ICON}  No checks performed.${RESET}\n\n"; return; fi

  local section_pb=""

  for result in "${results[@]}"; do
    IFS='|' read -r status item message <<< "$result"
    local item_short="$item"; if (( $(get_display_width "$item_short") > 20 )); then item_short="${item_short:0:17}..."; fi
    local pad_str=""; for ((i=0;i<$(( 20 - $(get_display_width "$item_short") ));i++)); do pad_str+=" "; done
    
    # Notice the double space after the icons below for cleaner alignment
    case "$status" in
      pass) 
        printf "  ${PASS_COLOR}✔  ${item_short}${pad_str} → ${PASS_ICON} ${ARROW_ICON} ${message}${RESET}\n" 
        section_pb+="${PB_PASS}"
        ;;
      warn) 
        printf "  ${WARN_COLOR}⚠  ${item_short}${pad_str} → ${WARN_ICON} ${ARROW_ICON} ${message}${RESET}\n" 
        section_pb+="${PB_WARN}"
        ;;
      fail) 
        printf "  ${FAIL_COLOR}✗  ${item_short}${pad_str} → ${FAIL_ICON} ${ARROW_ICON} ${message}${RESET}\n" 
        section_pb+="${PB_FAIL}"
        ;;
      info) 
        printf "  ${INFO_COLOR}ℹ  ${item_short}${pad_str} → ${INFO_ICON} ${ARROW_ICON} ${message}${RESET}\n" 
        section_pb+="${PB_INFO}"
        ;;
      skip) 
        printf "  ${SKIP_COLOR}↷  ${item_short}${pad_str} → ${SKIP_ICON} ${ARROW_ICON} ${message}${RESET}\n" 
        section_pb+="${PB_SKIP}"
        ;;
    esac
  done
  
  # Print the dynamically named progress bar at the bottom of each list
  printf "\n  ${BOLD}${INFO_COLOR}📊 %s Status: [ ${section_pb} ]${RESET}\n\n" "$category"
}

print_final_summary() { 
  print_section_header "FINAL SUMMARY" "$1"
  
  # Build total terminal progress string
  local term_pb=""
  for status in "${CHECK_STATUS_ARRAY[@]}"; do
    case "$status" in
      "P") term_pb+="${PB_PASS}" ;;
      "W") term_pb+="${PB_WARN}" ;;
      "F") term_pb+="${PB_FAIL}" ;;
      "I") term_pb+="${PB_INFO}" ;;
      "S") term_pb+="${PB_SKIP}" ;;
    esac
  done
  
  printf "  ${BOLD}${TOTAL_COLOR}🔥 Processed %d definitions${RESET}\n" "${#CHECK_STATUS_ARRAY[@]}"
  printf "  ${BOLD}${INFO_COLOR}📊 Overall Status: [ ${term_pb} ]${RESET}\n\n"
}

check_project_info() {
  for item in "${!PROJECT_INFO_REQUIREMENTS[@]}"; do
    local req_ver="${PROJECT_INFO_REQUIREMENTS["$item"]}"
    if ! version_ge "$project_version" "$req_ver"; then record_result "skip" "Project Information" "$item" "Planned for $req_ver."; continue; fi
    case "$item" in
      java)
        local req_java="${VERSION_REQUIREMENTS["java.version"]}"; local eff_java=$(resolve_property "$(get_tag_value "maven.compiler.release")")
        [[ -z "$eff_java" ]] && eff_java=$(resolve_property "$(get_tag_value "java.version")")
        if [[ -n "$eff_java" ]]; then version_ge "$eff_java" "$req_java" && record_result "pass" "Project Information" "Java" "$eff_java (min $req_java met)" || record_result "fail" "Project Information" "Java" "$eff_java < min $req_java"
        else record_result "fail" "Project Information" "Java" "Missing (Requires min $req_java)"; fi ;;
      *)
        local val=$(get_tag_value "$item"); [[ -z "$val" ]] && record_result "fail" "Project Information" "$item" "Required field missing" || record_result "pass" "Project Information" "$item" "$val" ;;
    esac
  done
}

check_dependencies() {
  declare -A checked_deps
  for dep in "${!DEPENDENCY_REQUIREMENTS[@]}"; do
    checked_deps["$dep"]=1; local req_ver="${DEPENDENCY_REQUIREMENTS["$dep"]}"; local min_ver="${VERSION_REQUIREMENTS["$dep"]}"
    local res_ver=$(resolve_property "$(get_version_by_artifact_id "$dep")")
    if ! version_ge "$project_version" "$req_ver"; then record_result "skip" "Dependencies" "$dep" "Planned for $req_ver"; continue; fi

    if [[ -n "$res_ver" ]]; then
      version_ge "$res_ver" "$min_ver" && record_result "pass" "Dependencies" "$dep" "v$res_ver (min $min_ver met)" || record_result "fail" "Dependencies" "$dep" "v$res_ver < min $min_ver"
    else
      if [[ "$IS_SNAPSHOT" == "true" && "$project_version" == "$req_ver" ]]; then
        record_result "warn" "Dependencies" "$dep" "Missing (Required for release, ignored in dev)"
      else
        record_result "fail" "Dependencies" "$dep" "Missing (Requires min $min_ver)"
      fi
    fi
  done
}

check_plugins() {
  declare -A checked_plugins
  for plugin in "${!PLUGIN_REQUIREMENTS[@]}"; do
    checked_plugins["$plugin"]=1; local req_ver="${PLUGIN_REQUIREMENTS["$plugin"]}"; local min_ver="${VERSION_REQUIREMENTS["$plugin"]}"
    local res_ver=$(resolve_property "$(get_version_by_artifact_id "$plugin")")
    if ! version_ge "$project_version" "$req_ver"; then record_result "skip" "Plugins" "$plugin" "Planned for $req_ver"; continue; fi

    if [[ -n "$res_ver" ]]; then
      version_ge "$res_ver" "$min_ver" && record_result "pass" "Plugins" "$plugin" "v$res_ver (min $min_ver met)" || record_result "fail" "Plugins" "$plugin" "v$res_ver < min $min_ver"
    else
      if [[ "$IS_SNAPSHOT" == "true" && "$project_version" == "$req_ver" ]]; then
        record_result "warn" "Plugins" "$plugin" "Missing (Required for release, ignored in dev)"
      else
        record_result "fail" "Plugins" "$plugin" "Missing (Requires min $min_ver)"
      fi
    fi
  done
}

main() {
  if [[ ! -f "$POM_FILE" ]]; then echo -e "${FAIL_COLOR}${BOLD}✗ Error: POM not found${RESET}"; exit 1; fi
  local raw_version=$(get_tag_value version)
  [[ "$raw_version" == *"-SNAPSHOT" ]] && IS_SNAPSHOT=true
  project_version="v${raw_version%-SNAPSHOT}"
  [[ -z "$project_version" || "$project_version" == "v" ]] && project_version="v0.0.0"
  project_stage="${MILESTONE_MAP["$project_version"]:-Unknown}"

  init_output_dir
  print_banner
  print_project_info
  
  check_project_info
  check_dependencies
  check_plugins
  
  # Finalize HTML after all checks populate the data arrays
  finalize_html_report

  print_section "Project Information" "✍ PROJECT INFORMATION" "$SECTION_PURPLE"
  print_section "Dependencies" "🏗 DEPENDENCIES" "$SECTION_CYAN"
  print_section "Plugins" "🔌 PLUGINS" "$SECTION_BLUE"
  print_final_summary "$SECTION_PURPLE"

  if [[ "$STRICT_MODE" == "true" && $((counts["fail"] + counts["warn"])) -gt 0 ]]; then exit 1; fi
  if [[ ${counts["fail"]} -gt 0 ]]; then exit 1; fi
  exit 0
}
main "$@"