#!/usr/bin/env bash
set -eo pipefail

CONFIG_FILE="${MOODLE_CONFIG_FILE:-/var/www/lms/public/config.php}"
BBB_URL="${BBB_URL:-https://meet.example.com}"
BBB_SECRET="${BBB_SECRET:-YOUR_BBB_SHARED_SECRET_HERE}"

if command -v mariadb >/dev/null 2>&1; then
    SQL_BIN="mariadb"
else
    SQL_BIN="mysql"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERROR] Moodle config file not found at $CONFIG_FILE"
    exit 1
fi

extract_cfg() {
    local key="$1"
    grep -E "^[[:space:]]*\\\$CFG->${key}[[:space:]]*=" "$CONFIG_FILE" \
        | head -n 1 \
        | sed -E "s/^[[:space:]]*\\\$CFG->${key}[[:space:]]*=[[:space:]]*['\"]([^'\"]*)['\"].*/\1/"
}

DB_HOST=$(extract_cfg "dbhost")
DB_NAME=$(extract_cfg "dbname")
DB_USER=$(extract_cfg "dbuser")
DB_PASS=$(extract_cfg "dbpass")
DB_PREFIX=$(extract_cfg "prefix")
MOODLE_WWWROOT=$(extract_cfg "wwwroot")

DB_HOST="${DB_HOST:-localhost}"
DB_NAME="${DB_NAME:-moodle}"
DB_USER="${DB_USER:-root}"
DB_PREFIX="${DB_PREFIX:-mdl_}"
MOODLE_HOST="${MOODLE_WWWROOT:-https://lms.example.com}"

run_sql() {
    local query="$1"
    MYSQL_PWD="$DB_PASS" "$SQL_BIN" -h "$DB_HOST" -u "$DB_USER" -D "$DB_NAME" --skip-column-names --batch --raw -e "$query" 2>/dev/null
}

# --- FINANCIAL YEAR & QUARTER CALCULATION (FY July 1 - June 30) ---
CURRENT_MONTH=$(date +%-m)
CURRENT_YEAR=$(date +%Y)

if [ -n "$1" ]; then
    TARGET_Q="$1"
else
    if [ "$CURRENT_MONTH" -ge 7 ] && [ "$CURRENT_MONTH" -le 9 ]; then
        TARGET_Q="Q1"
    elif [ "$CURRENT_MONTH" -ge 10 ] && [ "$CURRENT_MONTH" -le 12 ]; then
        TARGET_Q="Q2"
    elif [ "$CURRENT_MONTH" -ge 1 ] && [ "$CURRENT_MONTH" -le 3 ]; then
        TARGET_Q="Q3"
    else
        TARGET_Q="Q4"
    fi
fi

if [ "$CURRENT_MONTH" -ge 7 ]; then
    FY_START_YEAR=$CURRENT_YEAR
    FY_END_YEAR=$((CURRENT_YEAR + 1))
else
    FY_START_YEAR=$((CURRENT_YEAR - 1))
    FY_END_YEAR=$CURRENT_YEAR
fi

FY_LABEL="FY ${FY_START_YEAR}/${FY_END_YEAR}"

case "$TARGET_Q" in
    Q1)
        Q_NAME="Q1 (July 01 - September 30, ${FY_START_YEAR})"
        START_DATE="${FY_START_YEAR}-07-01 00:00:00"
        END_DATE="${FY_START_YEAR}-09-30 23:59:59"
        ;;
    Q2)
        Q_NAME="Q2 (October 01 - December 31, ${FY_START_YEAR})"
        START_DATE="${FY_START_YEAR}-10-01 00:00:00"
        END_DATE="${FY_START_YEAR}-12-31 23:59:59"
        ;;
    Q3)
        Q_NAME="Q3 (January 01 - March 31, ${FY_END_YEAR})"
        START_DATE="${FY_END_YEAR}-01-01 00:00:00"
        END_DATE="${FY_END_YEAR}-03-31 23:59:59"
        ;;
    Q4)
        Q_NAME="Q4 (April 01 - June 30, ${FY_END_YEAR})"
        START_DATE="${FY_END_YEAR}-04-01 00:00:00"
        END_DATE="${FY_END_YEAR}-06-30 23:59:59"
        ;;
    *)
        echo "[ERROR] Invalid Quarter specified. Use Q1, Q2, Q3, or Q4."
        exit 1
        ;;
esac

START_TIMESTAMP=$(date -d "$START_DATE" +%s)
END_TIMESTAMP=$(date -d "$END_DATE" +%s)

REPORT_LABEL="${FY_LABEL} ${TARGET_Q}"
OUT_FILE="./bbb_quarterly_report_${TARGET_Q}_$(date +%Y%m%d_%H%M%S).txt"

# --- BIGBLUEBUTTON API QUERIES ---
bbb_api_call() {
    local call_name="$1"
    local params="$2"
    local checksum_string="${call_name}${params}${BBB_SECRET}"
    local checksum
    checksum=$(echo -n "$checksum_string" | sha1sum | awk '{print $1}')
    
    local api_endpoint="${BBB_URL}/bigbluebutton/api/${call_name}"
    if [ -n "$params" ]; then
        curl -s -k "${api_endpoint}?${params}&checksum=${checksum}"
    else
        curl -s -k "${api_endpoint}?checksum=${checksum}"
    fi
}

MEETINGS_XML=$(bbb_api_call "getMeetings" "" || true)
RECORDINGS_XML=$(bbb_api_call "getRecordings" "state=published,unpublished" || true)

count_xml_tags() {
    local xml="$1"
    local tag="$2"
    echo "$xml" | awk -v pat="<${tag}>" 'BEGIN{c=0} {c+=gsub(pat, "")} END{print c}'
}

LIVE_MEETINGS_COUNT=$(count_xml_tags "$MEETINGS_XML" "meeting")
LIVE_CURRENT_USERS=0
if [ "$LIVE_MEETINGS_COUNT" -gt 0 ]; then
    PARTICIPANTS=$(echo "$MEETINGS_XML" | sed -n 's/.*<participantCount>\([0-9]*\)<\/participantCount>.*/\1/p')
    for count in $PARTICIPANTS; do
        LIVE_CURRENT_USERS=$((LIVE_CURRENT_USERS + count))
    done
fi

TOTAL_RECORDINGS_COUNT=$(count_xml_tags "$RECORDINGS_XML" "recording")

# --- DATABASE QUERIES ---
TOTAL_QUARTER_SESSIONS_SQL="
    SELECT COUNT(DISTINCT meetingid) 
    FROM ${DB_PREFIX}bigbluebuttonbn_logs 
    WHERE timecreated >= ${START_TIMESTAMP} 
      AND timecreated <= ${END_TIMESTAMP};
"
TOTAL_QUARTER_SESSIONS=$(run_sql "$TOTAL_QUARTER_SESSIONS_SQL" || echo "0")
TOTAL_QUARTER_SESSIONS="${TOTAL_QUARTER_SESSIONS:-0}"

TOP_COURSES_SQL="
    SELECT 
        c.id, 
        c.fullname, 
        COUNT(l.id) AS total_joins
    FROM ${DB_PREFIX}bigbluebuttonbn_logs l
    JOIN ${DB_PREFIX}course c ON l.courseid = c.id
    WHERE l.timecreated >= ${START_TIMESTAMP} 
      AND l.timecreated <= ${END_TIMESTAMP}
    GROUP BY c.id, c.fullname
    ORDER BY total_joins DESC
    LIMIT 20;
"
TOP_COURSES_DATA=$(run_sql "$TOP_COURSES_SQL" || true)

TOP_TEACHERS_SQL="
    SELECT 
        u.id, 
        CONCAT(u.firstname, ' ', u.lastname) AS full_name, 
        u.email, 
        r.name AS role_name,
        COUNT(l.id) AS session_interactions
    FROM ${DB_PREFIX}bigbluebuttonbn_logs l
    JOIN ${DB_PREFIX}user u ON l.userid = u.id
    JOIN ${DB_PREFIX}role_assignments ra ON ra.userid = u.id
    JOIN ${DB_PREFIX}context ctx ON ra.contextid = ctx.id AND (ctx.contextlevel = 50 AND ctx.instanceid = l.courseid)
    JOIN ${DB_PREFIX}role r ON ra.roleid = r.id
    WHERE l.timecreated >= ${START_TIMESTAMP} 
      AND l.timecreated <= ${END_TIMESTAMP}
      AND r.shortname IN ('editingteacher', 'teacher')
    GROUP BY u.id, full_name, u.email, r.name
    ORDER BY session_interactions DESC
    LIMIT 500;
"
TOP_TEACHERS_DATA=$(run_sql "$TOP_TEACHERS_SQL" || true)

# --- REPORT GENERATION ---
{
echo "===================================================================================================="
echo "      BIGBLUEBUTTON & MOODLE PLATFORM USAGE REPORT - ${FY_LABEL} ${TARGET_Q}                       "
echo "===================================================================================================="
echo "Execution Timestamp : $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "Reporting Period    : ${Q_NAME}"
echo "Moodle Host         : ${MOODLE_HOST}"
echo "Server Endpoint     : ${BBB_URL}"
echo "===================================================================================================="
echo ""
echo "----------------------------------------------------------------------------------------------------"
echo "1. QUARTERLY SESSION METRICS & LIVE INFRASTRUCTURE SNAPSHOT"
echo "----------------------------------------------------------------------------------------------------"
echo "Total BBB Sessions Conducted in ${TARGET_Q} : ${TOTAL_QUARTER_SESSIONS}"
echo "Total Server Recordings on File (All)   : ${TOTAL_RECORDINGS_COUNT}"
echo "Live Active Sessions (At execution time) : ${LIVE_MEETINGS_COUNT}"
echo "Live Connected Users (At execution time) : ${LIVE_CURRENT_USERS}"
echo ""
echo "----------------------------------------------------------------------------------------------------"
echo "2. TOP COURSES UTILIZING BIGBLUEBUTTON (${TARGET_Q})"
echo "----------------------------------------------------------------------------------------------------"
printf "%-10s | %-55s | %-12s\n" "COURSE ID" "COURSE NAME" "TOTAL JOINS"
echo "----------------------------------------------------------------------------------------------------"
if [ -n "$TOP_COURSES_DATA" ]; then
    echo "$TOP_COURSES_DATA" | while IFS=$'\t' read -r cid cname joins; do
        [ -n "$cid" ] && printf "%-10s | %-55.55s | %-12s\n" "$cid" "$cname" "$joins"
    done
else
    echo "No course join activity recorded during ${TARGET_Q}."
fi
echo ""
echo "----------------------------------------------------------------------------------------------------"
echo "3. TOP ACTIVE TEACHING STAFF / LECTURERS (UP TO 500) (${TARGET_Q})"
echo "----------------------------------------------------------------------------------------------------"
printf "%-8s | %-28s | %-32s | %-18s | %-8s\n" "USER ID" "LECTURER NAME" "EMAIL" "ROLE" "JOINS"
echo "----------------------------------------------------------------------------------------------------"
if [ -n "$TOP_TEACHERS_DATA" ]; then
    echo "$TOP_TEACHERS_DATA" | while IFS=$'\t' read -r uid uname uemail urole ucount; do
        [ -n "$uid" ] && printf "%-8s | %-28.28s | %-32.32s | %-18.18s | %-8s\n" "$uid" "$uname" "$uemail" "$urole" "$ucount"
    done
else
    echo "No teacher/lecturer interactions recorded during ${TARGET_Q}."
fi
echo ""
echo "----------------------------------------------------------------------------------------------------"
echo "4. STRATEGIC RECOMMENDATIONS FOR ODeL & SYSTEMS"
echo "----------------------------------------------------------------------------------------------------"
echo "* CAPACITY & CONCURRENCY PLANNING:"
echo "  - In ${TARGET_Q}, a total of ${TOTAL_QUARTER_SESSIONS} virtual class sessions were initiated."
echo "  - High-traffic courses identified in Section 2 should stagger start times (e.g. 10 minutes past the"
echo "    hour) to avoid simultaneous WebRTC DTLS handshakes at peak timetable slots."
echo ""
echo "* PEDAGOGICAL ENGAGEMENT (ODeL):"
echo "  - Section 3 highlights faculty actively driving virtual classroom adoption."
echo "  - Faculty members not appearing in the top 500 active tier may benefit from refresher orientation"
echo "    sessions on interactive whiteboard and breakout room capabilities."
echo ""
echo "* STORAGE RECOVERY:"
echo "  - Total cataloged recordings: ${TOTAL_RECORDINGS_COUNT}."
echo "  - Sessions recorded in ${TARGET_Q} should be reviewed at end of semester; recordings older than 6 months"
echo "    should be offloaded to archive cold storage to maintain high IOPS on root NVMe/SSD partitions."
echo "===================================================================================================="
echo "Developed by Nova Cloud Edges | www.ncloud.co.ug"
echo "===================================================================================================="
} > "$OUT_FILE"

# Dispatch email attachment via Moodle
MAILER_SCRIPT="$(dirname "$0")/send_bbb_mail.php"
if [ -f "$MAILER_SCRIPT" ]; then
    php "$MAILER_SCRIPT" "$OUT_FILE" "${REPORT_LABEL}"
elif [ -f "/var/www/lms/public/local/send_bbb_mail.php" ]; then
    php /var/www/lms/public/local/send_bbb_mail.php "$OUT_FILE" "${REPORT_LABEL}"
fi
