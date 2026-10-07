<?php
// phpx bootstrap: runs a PHP script or PHAR under FrankenPHP's php-cli with a
// php-compatible $argv. FrankenPHP >= 1.13 passes [binary, script, args...]
// where php (and FrankenPHP <= 1.12) pass [script, args...]; Symfony Console
// apps (Composer, PHPStan, PIE...) then read their own path as the command.
// Usage: frankenphp php-cli phpx-run.php <script> [args...]
$argv = $_SERVER['argv'];
while ($argv !== [] && realpath((string) $argv[0]) !== __FILE__) {
    array_shift($argv);
}
array_shift($argv);
if ($argv === []) {
    fwrite(STDERR, "phpx-run.php: missing script argument\n");
    exit(1);
}
$_SERVER['argv'] = $argv;
$_SERVER['argc'] = $argc = count($argv);
$_SERVER['SCRIPT_NAME'] = $_SERVER['SCRIPT_FILENAME'] = $_SERVER['PHP_SELF'] = $argv[0];
unset($argc);
$argc = count($argv);
require $argv[0];
