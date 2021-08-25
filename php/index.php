<?php
/**
 * Start PHP web server
 *
 * php -S 0.0.0.0:7999 index.php
 * curl -X PUT -T test.txt localhost:7999
 * PHP web server returns 200 for POST, so just handling PUT
 */

function _log($msg)
{
    $stderr = fopen('php://stderr', 'w');
    fwrite($stderr, $msg);
    fclose($stderr);
}

$headers = getallheaders();
foreach ($headers as $key => $val) {
    _log('    ' . $key . ': ' . $val . PHP_EOL);
}

// @see: https://www.php.net/manual/en/features.file-upload.put-method.php
$save_to = tempnam(sys_get_temp_dir(), 'put_');
$putdata = fopen("php://input", "r");
$fp = fopen($save_to, "w");
while ($data = fread($putdata, 1024))
    fwrite($fp, $data);
fclose($fp);
fclose($putdata);
_log("    Wrote PUT/POST data into '" . $save_to . "'" . PHP_EOL);