<?php
define('CLI_SCRIPT', true);

// Resolve Moodle config path
$config_candidates = [
    __DIR__ . '/../config.php',
    '/var/www/lms/public/config.php',
    '/var/www/html/config.php'
];

$loaded = false;
foreach ($config_candidates as $cand) {
    if (file_exists($cand)) {
        require($cand);
        $loaded = true;
        break;
    }
}

if (!$loaded) {
    fwrite(STDERR, "[ERROR] Unable to locate Moodle config.php\n");
    exit(1);
}

require_once($CFG->libdir . '/clilib.php');
require_once($CFG->libdir . '/moodlelib.php');

if (empty($argv[1]) || !file_exists($argv[1])) {
    cli_error("Report file not found or not specified.\n");
}

$report_filepath = realpath($argv[1]);
$report_filename = basename($report_filepath);
$quarter_label   = !empty($argv[2]) ? $argv[2] : "Financial Quarter";

if (!is_readable($report_filepath)) {
    cli_error("Report file is not readable: {$report_filepath}\n");
}

$subject = "[LMS / BBB Report] {$quarter_label} Usage & Capacity Audit - " . date('Y-m-d');

$body_text = "Dear Team,\n\n"
           . "Please find attached the automated BigBlueButton and Moodle platform usage audit for {$quarter_label}.\n\n"
           . "Report summary:\n"
           . "- Total distinct BigBlueButton sessions initiated during the quarter\n"
           . "- Current live snapshot & recording catalog status\n"
           . "- Top visited courses utilizing BigBlueButton\n"
           . "- Top 500 active teaching staff (Lecturers / Instructors)\n"
           . "- Architectural & capacity optimization recommendations\n\n"
           . "Best regards,\n"
           . "Directorate of ICT & e-Learning\n"
           . "Soroti University\n\n"
           . "---\n"
           . "Developed by Nova Cloud Edges | www.ncloud.co.ug";

// Primary administrative recipients
$recipients = [
    'systems@sun.ac.ug',
    'odel@sun.ac.ug'
];

$support_user = core_user::get_support_user();

foreach ($recipients as $email) {
    try {
        $mailer = get_mailer();
        $mailer->From     = $support_user->email;
        $mailer->FromName = fullname($support_user);
        $mailer->Subject  = $subject;
        $mailer->Body     = $body_text;
        
        $mailer->addAddress(trim($email));
        $mailer->addAttachment($report_filepath, $report_filename, 'base64', 'text/plain');
        
        if ($mailer->send()) {
            echo "[✓] Successfully sent report with attachment to: {$email}\n";
        } else {
            echo "[✗] Mailer Error for {$email}: " . $mailer->ErrorInfo . "\n";
        }
    } catch (Exception $e) {
        echo "[ERROR] Exception sending to {$email}: " . $e->getMessage() . "\n";
    }
}
