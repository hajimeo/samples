<?php
/**
 * php -S 0.0.0.0:7999 index.php
 * curl -X PUT -T test.txt localhost:7999
 * PHP web server returns 200 for POST, so just handling PUT
 */

// @see: https://www.php.net/manual/en/features.file-upload.put-method.php
$save_to = tempnam(sys_get_temp_dir(), 'put_');
$putdata = fopen("php://input", "r");
$fp = fopen($save_to, "w");
while ($data = fread($putdata, 1024))
    fwrite($fp, $data);
fclose($fp);
fclose($putdata);

$stderr = fopen('php://stderr', 'w');
fwrite($stderr, "Wrote PUT/POST data into '" . $save_to . "'" . PHP_EOL);
fclose($stderr);