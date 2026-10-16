Here is the plain-text version of your README, formatted for a `.txt` file without Markdown syntax.

Writing

# BIGBLUEBUTTON & MOODLE USAGE AUDITOR

Maintained by: Nova Cloud Edges Website: https://www.ncloud.co.ug Repository: https://github.com/linknixon/bbb-moodle-auditor License: MIT Platform: Moodle LMS | BigBlueButton

## DESCRIPTION

An automated reporting and auditing tool designed for higher education institutions to monitor BigBlueButton virtual classroom utilization, live concurrency, recording retention, and faculty adoption across institutional financial quarters.

Developed and maintained by Nova Cloud Edges.

## KEY FEATURES

1. FINANCIAL QUARTER ALIGNMENT (JULY 1 - JUNE 30)Automatically calculates Unix epoch timestamps for the institution's financial year.
   Q1: July 1 - September 30 Q2: October 1 - December 31 Q3: January 1 - March 31 Q4: April 1 - June 30
2. FACULTY ADOPTION AUDITIdentifies up to 500 active teaching staff assigned the editingteacher and teacher roles who initiate or participate in virtual sessions.
3. COURSE UTILIZATION RANKINGSIdentifies courses with high BigBlueButton usage to help network engineering teams plan WebRTC capacity and bandwidth requirements.
4. NATIVE MOODLE MAIL DISPATCHERSends reports as .txt email attachments through Moodle's built-in mail infrastructure using email\_to\_user() and PHPMailer.
5. PERFORMANCE AND SAFETYReads Moodle's dedicated BigBlueButton log table, mdl\_bigbluebuttonbn\_logs, using read-only SQL queries (SELECT).

## INSTALLATION AND SETUP

1. PREREQUISITESEnsure your server meets the following requirements:
   Install the required packages:
   sudo apt update sudo apt install -y git curl coreutils php-cli
   Note: awk and grep are normally installed by default on Ubuntu and Debian systems. Install them explicitly if missing.
   - Linux operating system: Ubuntu 20.04, 22.04, 24.04, or Debian.
   - Moodle LMS version 3.11 or later, including Moodle 4.x and 5.x.
   - MariaDB or MySQL database.
   - BigBlueButton server with API access enabled.
   - Required system packages: git, curl, awk, grep, sha1sum, coreutils, and php-cli.
2. CLONE THE REPOSITORYClone the repository into your preferred administrative directory:
   sudo git clone https://github.com/linknixon/bbb-moodle-auditor.git /opt/bbb-moodle-auditor
   Navigate to the project directory:
   cd /opt/bbb-moodle-auditor
   Make the reporting script executable:
   sudo chmod +x bbb\_moodle\_report.sh
3. DEPLOY THE MOODLE MAIL DISPATCHERCopy the mail dispatcher into the local directory within your Moodle web root:
   sudo cp /opt/bbb-moodle-auditor/send\_bbb\_mail.php /var/www/lms/public/local/send\_bbb\_mail.php
   Set the appropriate ownership:
   sudo chown www-data:www-data /var/www/lms/public/local/send\_bbb\_mail.php
   Set file permissions:
   sudo chmod 644 /var/www/lms/public/local/send\_bbb\_mail.php
   IMPORTANT: Replace /var/www/lms/public with the actual path to your Moodle web root. Ensure the local directory exists before copying the file.
4. CONFIGURE THE AUDITOROpen the reporting script:
   sudo nano /opt/bbb-moodle-auditor/bbb\_moodle\_report.sh
   Update the configuration variables near the top of the file.
   CONFIG\_FILE The absolute path to Moodle's config.php file.
   Example: /var/www/lms/public/config.php
   BBB\_URL The base URL of your BigBlueButton server.
   Example: https://meet.example.ac.ug
   BBB\_SECRET The shared secret used to authenticate BigBlueButton API requests.
   Obtain the secret by running the following command on the BigBlueButton server:
   bbb-conf --secret
   Example configuration:
   CONFIG\_FILE="/var/www/lms/public/config.php" BBB\_URL="https://meet.example.ac.ug" BBB\_SECRET="YOUR\_BBB\_SHARED\_SECRET"
   Use the actual variable names and syntax expected by your script if they differ from these examples.
5. CONFIGURE EMAIL RECIPIENTSOpen the Moodle mail dispatcher:
   sudo nano /var/www/lms/public/local/send\_bbb\_mail.php
   Configure the intended report recipients according to the variables and structure defined in the PHP file.
   Verify that Moodle's outgoing email settings are configured under:
   Site administration \> Server \> Email \> Outgoing mail configuration
   SECURITY NOTE: Keep the BigBlueButton shared secret confidential. Restrict access to configuration files and avoid exposing secrets in logs, source repositories, or email reports.

## USAGE INSTRUCTIONS

1. MANUAL EXECUTIONRun the reporting script without arguments to audit the current financial quarter:
   sudo /opt/bbb-moodle-auditor/bbb\_moodle\_report.sh
   To audit a specific financial quarter, use the corresponding quarter identifier:
   Q1: sudo /opt/bbb-moodle-auditor/bbb\_moodle\_report.sh Q1
   Q2: sudo /opt/bbb-moodle-auditor/bbb\_moodle\_report.sh Q2
   Q3: sudo /opt/bbb-moodle-auditor/bbb\_moodle\_report.sh Q3
   Q4: sudo /opt/bbb-moodle-auditor/bbb\_moodle\_report.sh Q4
   The script uses the configured financial calendar to determine the relevant reporting period.
   NOTE: Confirm the script's argument-handling logic if you intend to run reports for historical financial years. The quarter identifier alone may not specify a particular year.
2. AUTOMATED SCHEDULING WITH CRONSchedule the report to run automatically at 06:00 AM on the first day of each calendar quarter:
   January 1 April 1 July 1 October 1
   Open the root user's crontab:
   sudo crontab -e
   Add the following entry:
   0 6 1 1,4,7,10 \* /opt/bbb-moodle-auditor/bbb\_moodle\_report.sh \>\> /var/log/bbb\_quarterly\_report.log 2\>&1
   This configuration:
   Verify the cron schedule:
   sudo crontab -l
   Monitor execution logs:
   sudo tail -f /var/log/bbb\_quarterly\_report.log
   IMPORTANT: The cron schedule follows calendar-quarter boundaries, while the reporting year runs from July through June. Ensure the script's default logic selects the intended financial quarter on each scheduled date.
   - Runs the script at 06:00 AM on January 1, April 1, July 1, and October 1.
   - Appends standard output and error output to the log file.
   - Uses the script's default quarter-selection logic.

## OUTPUT REPORT STRUCTURE

The generated .txt report contains the following sections.

1. QUARTERLY SESSION METRICS AND LIVE SNAPSHOTSummarizes BigBlueButton activity during the selected reporting period, including:
   - Total sessions initiated during the quarter.
   - Number of live rooms running at the time of the snapshot.
   - Total recordings stored, as supported by the available data.
2. TOP COURSES UTILIZING BIGBLUEBUTTONRanks courses according to reported BigBlueButton activity.
   Information includes:
   These statistics help identify high-traffic courses and support bandwidth and WebRTC capacity planning.
   - Course ID.
   - Course name.
   - Total session joins.
3. TOP 500 TEACHING STAFFLists up to 500 teaching staff members identified by the audit.
   Information includes:
   These results help administrators assess faculty adoption of virtual classrooms across the institution.
   - User ID.
   - Lecturer name.
   - Institutional email address.
   - Moodle role.
   - Recorded interaction count.
4. STRATEGIC CAPACITY RECOMMENDATIONSProvides operational insights to support Open, Distance and eLearning (ODeL) teams and systems administrators.
   Recommendations may address:
   Interpret recommendations in the context of the institution's infrastructure, retention policies, and reporting data.
   - Virtual classroom concurrency.
   - Network and WebRTC capacity.
   - Recording storage and retention.
   - BigBlueButton adoption and utilization trends.

## SECURITY AND PERFORMANCE

The auditor is designed to use Moodle's BigBlueButton activity logs for reporting while minimizing its impact on the production environment.

- READ-ONLY REPORTING: Audit queries are intended to use SELECT statements against the relevant Moodle log table.
- CREDENTIAL PROTECTION: Store BigBlueButton secrets securely and restrict access to scripts containing credentials.
- EMAIL DELIVERY: Use Moodle's configured mail infrastructure for consistent institutional email delivery.
- ACCESS CONTROL: Restrict access to reports containing staff names, institutional email addresses, and usage information.
- OPERATIONAL MONITORING: Review cron logs and report output periodically to detect failures or unexpected results.

DISCLAIMER: Read-only database queries do not, by themselves, guarantee complete system safety. Validate query performance, permissions, and compatibility with your Moodle and BigBlueButton versions before production deployment.

## LICENSE

This project is distributed under the MIT License.

Refer to the LICENSE file in the repository for the complete license terms.

## MAINTAINED BY

Nova Cloud Edges

Website: https://www.ncloud.co.ug

Repository: https://github.com/linknixon/bbb-moodle-auditor

Supporting institutions with cloud infrastructure, virtual learning environments, and reliable digital education systems.

To save it: Copy the contents into a plain-text editor and save the file as `README.txt` using UTF-8 encoding.
