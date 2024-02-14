<?php
/**
 * Start PHP web server and accept GET/PUT/POST requests, and return specific request based on REQUEST_URI.
 * Useful for testing webhook
 *
 * php -S 0.0.0.0:7999 ./index.php
 * curl -X PUT -T test.txt localhost:7999
 *
 * To check mime type:
 *  $ file --mime-type sisu-odata4j-0.0.7.jar
 *  sisu-odata4j-0.0.7.jar: application/zip
 */

function _log($msg)
{
    $stderr = fopen('php://stderr', 'w');
    fwrite($stderr, $msg);
    fclose($stderr);
}

#https://stackoverflow.com/questions/41427359/phpunit-getallheaders-not-work
if (!function_exists('getallheaders')) {
    function getallheaders() {
        $headers = [];
        foreach ($_SERVER as $name => $value) {
            if (substr($name, 0, 5) == 'HTTP_') {
                $headers[str_replace(' ', '-', ucwords(strtolower(str_replace('_', ' ', substr($name, 5)))))] = $value;
            }
        }
        return $headers;
    }
}

function _log_headers($header_only = false)
{
    $headers = getallheaders();
    if ($header_only) {
        foreach ($headers as $key => $val) {
            _log('    ' . $key . ': ' . $val . PHP_EOL);
        }
    } else {
        foreach ($_SERVER as $key => $val) {
            _log('    ' . $key . ': ' . $val . PHP_EOL);
        }
    }
}

// NOTE: PHP's web server returns 200 for POST, so just handling PUT
function put_handler()
{
    // @see: https://www.php.net/manual/en/features.file-upload.put-method.php
    $save_to = tempnam(sys_get_temp_dir(), 'put_');
    $putdata = fopen("php://input", "r");
    $fp = fopen($save_to, "w");
    while ($data = fread($putdata, 1024))
        fwrite($fp, $data);
    fclose($fp);
    fclose($putdata);
    _log("    Wrote PUT/POST data into '{$save_to}'" . PHP_EOL);
}

function get_handler()
{
    $req = $_SERVER['REQUEST_URI'];

    if (stripos($req, "/junit-4.12.pom") > 0) {
        header("Content-Type: junit-4.12.pom");
        _return_file('./junit-4.12.pom');
        _log("    Handled $req " . PHP_EOL);
        return;
    }

    /*
     * dd if=/dev/zero of=./some-test-3.0.496-RELEASE.jar bs=89552991 count=1
     * #zip -0 ./some-test-3.0.496-RELEASE.jar ./dummy.img   # this still changes the size
     * jar -c0vf ./some-test-3.0.496-RELEASE.jar ./dummy.img # this adds MANIFEST.MF so the size changes
     */
    if (stripos($req, "/some-test-3.0.496-RELEASE.jar") > 0) {
        header("Content-Type: application/gzip");
        _return_file('./some-test-3.0.496-RELEASE.jar');
        _log("    Handled $req " . PHP_EOL);
        return;
    }

    if (stripos($req, "/manifests/5.3.33-66ddce6") > 0) {
        header("Docker-Content-Digest: sha256:c46d23046a71f0216a881f6976a67f9f2309d9420d7e0585db5f3dd11dc333dc");
        header("Content-Type: application/vnd.docker.distribution.manifest.v1+prettyjws");
        _return_file('./5.3.33-66ddce6-click-path-on-ui.json');
        _log("    Handled $req " . PHP_EOL);
        return;
    }

    if (stripos($req, "bebde28f893fa9594dadcaa7d6b8e2aa0299df20.tgz") > 0) {
        header("etag: \"b46d217ef54c01c394b798e22f253c19\"");
        header("Content-Type: application/gzip");
        _return_file('./caniuse-lite-1.0.30001159.tgz');
        _log("    Handled $req " . PHP_EOL);
        return;
    }

    if (stripos($req,"/repository/npm-test/caniuse-lite") === 0) {
        $name = './npmjs-lwc_caniuse-lite_mod.json';

        // Example of changing header by 'Accept: ' header
        //$name = './no-header.json';
        //if (stripos($_SERVER['HTTP_ACCEPT'], "application/vnd.npm.install-v1+json") !== false) {
        //    $name = ./with-header.json';
        //}

        header("Content-Type: application/json");
        _return_file($name);
        _log("    Handled $req " . PHP_EOL);
        return;
    }
    _log("    No handler for $req " . PHP_EOL);
}

function _return_file($path)
{
    // send the basic headers
    header("Content-Length: " . filesize($path));
    header("Last-Modified: " . date("D, d M Y H:i:s", filemtime($path)) . " " . date('T'));
    $fp = fopen($path, 'rb');
    fpassthru($fp);
    fclose($fp);
}

function main() {
    //error_reporting(E_ALL);
    //_log_headers();
    _log_headers(true);
    get_handler();
    if (in_array($_SERVER['REQUEST_METHOD'], ['GET'])) {
        get_handler();
    }
    else if (in_array($_SERVER['REQUEST_METHOD'], ['POST', 'PUT'])) {
        put_handler();
    }
}

main();
exit();