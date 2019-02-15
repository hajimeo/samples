var DEFAULT_SFAPI_VERSION = "35.0";
var setupUrls = {"/$":1, "/setup":1, "/saml":1, "/qa":1, "/jslibrary":1, "/one":1, "/content/session":1, 
    "/ui":1, "/layouteditor":1, "/apexpages":1, "/secur":1,"/home/home.jsp":1,".*page/timeoutwarn.jsp":1};
addKeyPrefixRegExps();
var fullpathRegexps = ["\\btsid="];
var debugEnabled = 0;

chrome.tabs.onRemoved.addListener(removeFrozenTab);

chrome.webRequest.onBeforeRequest.addListener(openInConsole,
    {urls: ['*://*.lightning.force.com/*'], types: ["main_frame"]});

chrome.webNavigation.onCommitted.addListener(specialCaseFrozenTab,
    {url: [{hostSuffix: 'lightning.force.com'}]});

var whitelistRegExps = [];

loadOptions();

function debug(line) {
    if (debugEnabled) console.log(line);
}

var injectedTabs = {};
var frozenTabs = {};
function insertFrozenTab(id) {
    frozenTabs[id] = 1;
    debug("Frozen tab added = " + id);
}

function isFrozen(id) {
    return frozenTabs.hasOwnProperty(id);
}

function removeFrozenTab(tabId, details) {
    if (isFrozen(tabId)) {
        delete(frozenTabs[tabId]);
        debug("Frozen tab removed = " + tabId);
    }
}

function getUrlPath(url) {
    return new URL(url).pathname;
}

function checkRegExps(str, regExps, startsWith) {
    for(var i = 0; i < regExps.length; i++) {
        var re = regExps[i];
        if (startsWith) re = "^" + re;
        if (new RegExp(re).test(str)) {
            debug("Matched regex: " + re);
            return true;
        }
    }
    return false;
}

function startsWithRegExps(url,regExps) {
    var path = getUrlPath(url);
    return checkRegExps(path, regExps, true);
}

function checkFullPathRegexps(url) {
    var path = getUrlPath(url);
    var fullpath = url.substring(url.indexOf(path), url.length);
    return checkRegExps(fullpath, fullpathRegexps, false);
}

// Identify if it is one of basic Gus urls such as home, console, logout etc
function isBaseOrgUrl(url) {
    var regexps = ["/?$","/home/home.jsp","/lightning/","/logout.jsp",".*page/timeoutwarn.jsp"];
    return startsWithRegExps(url, regexps);
}

function isConsoleUrl(url) {
    return startsWithRegExps(url, ["/lightning/"]);
}

function isAppUrl(url) {
    // An app url must contain tsid
    // May or may not be console app
    return new RegExp("\\btsid=").test(url);
}

function isConsoleBookmarkableUrl(url) {
    // A bookmarkable url must contain # optionally followed by
    // tab params
    return new RegExp("/lightning/\\??.*#").test(url);
}

// URLs to simply not touch
function ignoreUrl(url) {
    if (startsWithRegExps(url,["/005\\w"])) return url.indexOf("noredirect=1") > -1;
    return checkFullPathRegexps(url) || startsWithRegExps(url, Object.keys(setupUrls));
}

function checkWhitelistServers(url) {
    if (whitelistRegExps.length == 0) return true;
    var host = new URL(url).hostname;
    return checkRegExps(host, whitelistRegExps, false);
}

function specialCaseFrozenTab(details) {
    if (details.frameId !== 0) return;
    var newTabId = details.tabId;
    if (isFrozen(newTabId)) {
        // If a  user types in a new url on a setup tab, it would be given a fair chance to open in Console
        if ((details.transitionType == "link" || details.transitionType == "form_submit") &&
            (details.transitionQualifiers.indexOf("from_address_bar") == -1)) {
            debug("SPECIAL CASE - Frozen tab keep frozen = " + newTabId);
            return;
        }
        debug("SPECIAL CASE - unfreezing and opening normally");
        setTimeout(function() {
            removeFrozenTab(newTabId);
            openInConsole(details);
        }, 25);
    }
}

function openInConsole(details) {
    if (details.frameId !== 0) return;

    var newTabId = details.tabId;
    if (injectedTabs[newTabId]) return;

    var url = details.url;
    debug("NEW Request: TabID = " + newTabId + " url = " + url);

    if (!checkWhitelistServers(url)) {
        debug("Server not in white listed servers");
        return;
    }

    // If window is a popup, do not take any action
    // Allow only window type "normal"
    chrome.tabs.get(newTabId, function(tab){
        if(chrome.runtime.lastError) {
            debug(chrome.runtime.lastError.message);
            return;
        }
        if (! tab) return;

        var onlyfocus = false;

        if (isConsoleUrl(url)) {
            init(url);
            removeFrozenTab(newTabId);
            if (isAppUrl(url)) {
                return;
            } else {
                onlyfocus = !isConsoleBookmarkableUrl(url);
            }
            //onlyfocus = (getUrlPath(url) === "/console");
        } else {
            if (isFrozen(newTabId)) return;

            if (isAppUrl(url)) {
                debug("Ignoring another app url");
                insertFrozenTab(newTabId);
                return;
            }

            // If "Parent" tab is froxen, Child" tab is frozen too
            if(isFrozen(tab.openerTabId)) {
                debug("Freezing child of a frozen parent");
                insertFrozenTab(newTabId);
                return;
            }

            if (ignoreUrl(url)) { 
                debug("Ignoring setup url: " + url);
                insertFrozenTab(newTabId);
                return;
            }
        }

        // If it is a basic Gus url such as /console, do not open it in existing console
        // var onlyfocus = isBaseOrgUrl(url); 

        chrome.windows.get(tab.windowId, function(win){
            if (win.type == "normal") {

                // Note: Use hostname and not host , to ignore the port number.
                // You get access to all ports on the host
                var orgHost = new URL(url).hostname;
                
                // Find the tab with /console open
                chrome.tabs.query({url:"*://" + orgHost + "/lightning/*"}, function(tabs) {
                    if (typeof tabs !== 'undefined' && tabs.length > 0) {
                        var consoleTabId = tabs[0].id;
                        // An extra check in case of duplicate invocation
                        if (injectedTabs[newTabId]) return;
                        // Close new tab opened for the url
                        if (consoleTabId != newTabId) {
                            chrome.tabs.remove(newTabId);
                            if(chrome.runtime.lastError) {
                                debug(chrome.runtime.lastError.message);
                                return;
                            }

                            // Focus on the window that has Console tab open
                            chrome.tabs.get(consoleTabId, function(tab){
                                chrome.windows.update(tab.windowId, {focused:true});
                            });
                            // Focus on the console tab itself
                            chrome.tabs.update(consoleTabId, {selected: true});

                            if (!onlyfocus) {
                                if (!injectedTabs[newTabId]) {
                                    injectedTabs[newTabId] = 1;
                                    if (startsWithRegExps(url, ["/0D5"])) {
                                        processFeedItemUrl(consoleTabId, url)
                                    } else {
                                        injectTabInConsole(consoleTabId, url);
                                    }
                                } else {
                                    debug("REJECTED!!!!!!");
                                }
                            }
                            else {
                                debug("just navigate to existing console");
                            }
                        }
                    }
                    else {
                        debug("no console found, so just load page");
                    }
                });
            }
            else {
                debug("Window type not normal");
            }
        });
    });
}

function processFeedItemUrl(consoleTabId, url) {
    debug("Feed item url = " + url);
    // Need "isdtp=vw" for Console
    if (new URL(url).search === "") url += "?isdtp=vw"; else url = url.replace("?","?isdtp=vw&");
    var req = new XMLHttpRequest();
    req.onload = function() {
        var html = this.response;
        debug(html);
        var scriptTags = html.getElementsByTagName('script');
        if (scriptTags.length > 0) {
            var singleTickUrl = "'([^']+)'";
            var regexpsToTry = [
                "fireBeforeRedirectPage.+?" + singleTickUrl,
                "handleRedirect.+?" + singleTickUrl,
                "window.location.href.+?" + singleTickUrl,
                "window.location.replace.+?" + singleTickUrl,
            ];
            for (i = 0; i < scriptTags.length; i++) {
                var scriptTag = scriptTags[i];
                for (j = 0; j < regexpsToTry.length; j++) {
                    var reg = new RegExp(regexpsToTry[j]);
                    var regExec;
                    if (regExec = reg.exec(scriptTag.textContent)) {
                        var redirectUrl = regExec[1];
                        debug("Feed item redirectUrl: " + redirectUrl);
                        injectTabInConsole(consoleTabId, redirectUrl);
                        return;
                    }
                }
            }
        }
    }
    req.open("GET", url);
    req.responseType = 'document';

    req.send();
}

function injectTabInConsole(consoleTabId, url) {
    var insidecode = "var url=\"" + url + "\";" +
    "Sfdc.support.servicedesk.isConsoleTabLink(url)?Sfdc.support.servicedesk.openConsoleTabLink(url):" +
    "Sfdc.support.servicedesk.ApiHandler.openPrimaryTab({url:url,activate:true},undefined,function(){})";
    chrome.tabs.executeScript(consoleTabId,{
        "code": "var myScript = document.createElement('script');"
        + "myScript.textContent = '" + insidecode + "';"
        + "document.head.appendChild(myScript);"
    });
    debug("inject tab into existing console");
}

function parseSetupTree(html) {
    var setupNavTree = html.getElementById('setupNavTree');
    if (! setupNavTree) return;
    var allLinks = setupNavTree.getElementsByClassName("parent");
    var strName;
    var as;
    var strNameMain;
    var strName;
    var cmds = {};

    for(var i = 0; i<allLinks.length;i++) {
        var as = allLinks[i].getElementsByTagName("a");
        for(var j = 0;j<as.length;j++) {
            if(as[j].id.indexOf("_font") != -1) {
                strNameMain = 'Setup > ' + as[j].text + ' > ';
                break;
            }
        }
        var children = allLinks[i].querySelectorAll('.childContainer > .setupLeaf > a');
        for(var j = 0;j<children.length;j++) {
            if(children[j].text.length > 2) {
                strName = strNameMain + children[j].text;
                path = getUrlPath(children[j].href);
                setupUrls[path] = 1;
            }
        }
    }
    debug(setupUrls);
}

function getSetupTree(serverInstance) {
    var theurl = serverInstance + '/ui/setup/Setup'
    var req = new XMLHttpRequest();
    req.onload = function() {
        parseSetupTree(this.response);
    }
    req.open("GET", theurl);
    req.responseType = 'document';

    req.send();
}

function init(url) {
    debug("init url for url: " + url);
    var serverInstance = new URL(url).origin;
    chrome.cookies.get({url:url, name:'sid'},
        function(cookie) {
            if (! cookie) return;
            sid = cookie.value;
            clientId = sid.split('!')[0];
            hash = clientId + '!' + sid.substring(sid.length - 10, sid.length);
            if (! setupUrls[hash]) {
                debug("Compiling setupUrls");
                getSetupTree(serverInstance);
                setupUrls[hash] = 1;
            } else {
                debug("Already loaded setupUrls");
            }
        }
    );
}

function loadOptions() {
    chrome.storage.sync.get({
        whitelistRegExps: '*',
        debug: 0
    }, function(items) {
        loadwhitelistRegExps(items.whitelistRegExps);
        debugEnabled = items.debug;
    });

    // Perform a reload any time the user clicks "Save"
    chrome.storage.onChanged.addListener(function(changes, namespace) {
        for (key in changes) {
            if (key === "debug") debugEnabled = changes[key].newValue;
            if (key === "whitelistRegExps") loadwhitelistRegExps(changes[key].newValue);
        }
    });
}

function loadwhitelistRegExps(input) {
    whitelistRegExps = [];
    input = input.trim();
    debug("Loading white list servers: " + input);
    if (input !== "") {
        var list = input.split(",");
        for(var i=0; i < list.length; i++) {
            var re = list[i];
            try {
                new RegExp(re);
                whitelistRegExps.push(re);
            } catch(e) {
                // Invalid regular expression
            }
        }
    }

    // Init "existing" console tabs, if any
    chrome.tabs.query({url:"*://*.lightning.force.com/lightning/*"}, function(tabs) {
        if (typeof tabs !== 'undefined' && tabs.length > 0) {
            for (var i = 0; i < tabs.length; i++) {
                if (checkWhitelistServers(tabs[i].url)) {
                    init(tabs[i].url);
                }
            }
        }
    });
}

function addKeyPrefixRegExps() {
    var setupKeyPrefixes = [
        '005', '00B', '00C', '00D', '00E', '00G', '00N', '00S', '00X', '00b', '00c', 
        '00e', '00h', '00l', '00m', '00n', '00p', '011', '012', '013', '014', '016', 
        '019', '01A', '01B', '01C', '01D', '01G', '01H', '01I', '01J', '01L', '01N', 
        '01O', '01P', '01Q', '01R', '01S', '01T', '01U', '01V', '01W', '01X', '01b', 
        '01c', '01d', '01e', '01g', '01h', '01i', '01j', '01k', '01l', '01m', '01p', 
        '01q', '01r', '022', '023', '024', '025', '026', '02B', '02C', '02E', '02F', 
        '02G', '02H', '02I', '02K', '02L', '02M', '02R', '02S', '02T', '02U', '02V', 
        '02X', '02Y', '02b', '02d', '02f', '02g', '02h', '02j', '02k', '02l', '02m', 
        '02n', '02p', '02q', '02t', '02u', '02v', '02w', '02x', '030', '031', '032', 
        '033', '034', '035', '03C', '03L', '03a', '03c', '03d', '03e', '03f', '03g', 
        '03i', '03k', '03n', '03q', '03u', '041', '042', '043', '044', '045', '046', 
        '04E', '04F', '04H', '04P', '04S', '04T', '04Y', '04a', '04b', '04c', '04d', 
        '04e', '04f', '04j', '04k', '04l', '04m', '04n', '04o', '04p', '04q', '04r', 
        '04s', '04t', '04u', '04v', '04w', '04x', '04y', '04z', '050', '051', '052', 
        '053', '054', '055', '056', '058', '05A', '05E', '05F', '05G', '05O', '05P', 
        '05Q', '05R', '05S', '05U', '05X', '05c', '05d', '05e', '05t', '060', '062', 
        '063', '064', '065', '066', '067', '06B', '06F', '06G', '06H', '06I', '06J', 
        '06K', '06L', '06M', '06N', '06O', '06P', '06Q', '06R', '06S', '06T', '06U', 
        '06V', '06W', '06X', '06Y', '06Z', '06a', '06c', '06d', '06e', '06f', '06g', 
        '06j', '06s', '06t', '070', '071', '072', '073', '074', '076', '077', '078', 
        '07A', '07B', '07C', '07D', '07E', '07J', '07K', '07L', '07M', '07O', '07R', 
        '07S', '07T', '07U', '07V', '07W', '07X', '07Y', '07Z', '07e', '07g', '07h', 
        '07i', '07l', '07n', '07o', '07q', '07u', '080', '081', '082', '084', '086', 
        '088', '08B', '08D', '08E', '08F', '08J', '08K', '08L', '08O', '08S', '08V', 
        '08W', '08X', '08a', '08e', '08g', '090', '091', '092', '093', '094', '095', 
        '096', '097', '099', '09D', '09H', '09I', '09J', '09L', '09M', '09P', '09Q', 
        '09R', '09S', '09T', '09U', '09V', '09Z', '09a', '09b', '09d', '09e', '09f', 
        '09g', '09j', '0A0', '0A1', '0A2', '0A3', '0A4', '0A5', '0A7', '0AA', '0AB', 
        '0AC', '0AD', '0AH', '0AI', '0AJ', '0AK', '0AL', '0AM', '0AN', '0AO', '0AP', 
        '0AQ', '0AR', '0AS', '0AT', '0AU', '0AV', '0AX', '0AZ', '0Ab', '0Ac', '0Ad', 
        '0Ae', '0Af', '0Ai', '0Aj', '0Ak', '0Al', '0Am', '0Ao', '0Ap', '0Ar', '0As', 
        '0Ax', '0Az', '0B0', '0B1', '0B2', '0B3', '0B9', '0BA', '0BB', '0BC', '0BE', 
        '0BF', '0BH', '0BJ', '0BL', '0BP', '0BT', '0BU', '0BX', '0BZ', '0Ba', '0Bb', 
        '0Bd', '0Be', '0Bf', '0Bh', '0Bi', '0Bj', '0Bk', '0Bl', '0Bm', '0Bn', '0Bo', 
        '0Bp', '0Bq', '0Br', '0Bw', '0By', '0C0', '0C1', '0C2', '0C5', '0C6', '0C7', 
        '0C9', '0CA', '0CB', '0CD', '0CF', '0CG', '0CI', '0CJ', '0CK', '0CL', '0CO', 
        '0CP', '0CS', '0CU', '0CX', '0Ca', '0Cb', '0Cc', '0Cg', '0Ci', '0Cy', '0D0', 
        '0D1', '0D2', '0D3', '0D8', '0DA', '0DB', '0DC', '0DD', '0DE', '0DF', '0DG', 
        '0DH', '0DJ', '0DL', '0DM', '0DN', '0DO', '0DQ', '0DR', '0DS', '0DT', '0DU', 
        '0DV', '0DW', '0DX', '0DY', '0Da', '0Db', '0Dd', '0Df', '0Dk', '0Dl', '0Dp', 
        '0Dq', '0E0', '0E1', '0E2', '0E3', '0E4', '0E5', '0E6', '0EA', '0EC', '0ED', 
        '0EE', '0EH', '0EI', '0EJ', '0EN', '0EO', '0EP', '0EQ', '0ER', '0EV', '0EW', 
        '0EX', '0EZ', '0Eb', '0Ee', '0Ef', '0Eg', '0Eh', '0Ei', '0Ej', '0Ek', '0Em', 
        '0Eo', '0Eq', '0Er', '0Es', '0Eu', '0Ev', '0F0', '0F1', '0F2', '0F4', '0F6', 
        '0F8', '0FA', '0FC', '0FD', '0FE', '0FG', '0FI', '0FJ', '0FK', '0FL', '0FM', 
        '0FN', '0FQ', '0FR', '0FS', '0FV', '0FW', '0FX', '0FY', '0FZ', '0Fa', '0Fb', 
        '0Fc', '0Fd', '0Fe', '0Fg', '0Fh', '0Fi', '0Fj', '0Fl', '0Fm', '0Fn', '0Fv', 
        '0Fz', '0G0', '0G1', '0GB', '0GC', '0GG', '0GH', '0GI', '0GJ', '0GM', '0GN', 
        '0GO', '0GP', '0GQ', '0GR', '0GX', '0H0', '0H2', '0H3', '0H4', '0H5', '0H7', 
        '0H8', '0HB', '0HC', '0HD', '0HE', '0HG', '0HJ', '0HL', '0HM', '0HN', '0HO', 
        '0HS', '0HT', '0HU', '0HV', '0HW', '0HZ', '0Ha', '0Hb', '0Hc', '0Hd', '0He', 
        '0Hi', '0Hj', '0Hk', '0Hl', '0I3', '0I4', '0IA', '0IG', '0IO', '0IR', '0IS', 
        '0IT', '0IU', '0IW', '0IX', '0IY', '0Ia', '0Ie', '0If', '0Ih', '0Ik', '0Il', 
        '0In', '0Io', '0Iq', '0Ir', '0Is', '0It', '0Iu', '0Iv', '0Ix', '0J0', '0J2', 
        '0J4', '0J5', '0J8', '0JD', '0JE', '0JH', '0JI', '0JJ', '0JK', '0JL', '0JN', 
        '0JU', '0JW', '0JX', '0Jc', '0Jd', '0Je', '0Jf', '0Jg', '0Jj', '0Jn', '0Jo', 
        '0Jq', '0Js', '0Jt', '0Ju', '0Jv', '0Jw', '0Jx', '0Jy', '0K0', '0K2', '0K3', 
        '0K4', '0K6', '0K7', '0K9', '0KA', '0KB', '0KC', '0KD', '0Kq', '0L0', '0L1', 
        '0L2', '0L3', '0L4', '0L5', '0LC', '0LD', '0LE', '0LG', '0LJ', '0LK', '0LL', 
        '0LM', '0LN', '0Lc', '0Ld', '0Lm', '0M0', '0M1', '0M2', '0M5', '0M9', '0ME', 
        '0MF', '0MG', '0MI', '0MK', '0MR', '0Ma', '0Mi', '0Mr', '0N0', '0N5', '0N9', 
        '0NB', '0NC', '0ND', '0NE', '0NF', '0NG', '0NH', '0NI', '0NL', '0NM', '0NN', 
        '0NO', '0NP', '0NS', '0NT', '0NU', '0NV', '0NW', '0NY', '0Na', '0Nb', '0Nc', 
        '0Nd', '0Ne', '0Nf', '0Nk', '0Nl', '0Nn', '0No', '0Np', '0Nq', '0Nr', '0Ns', 
        '0Nt', '0Nu', '0Nv', '0Nx', '0Ny', '0Nz', '0O2', '0O5', '0P0', '0P1', '0P2', 
        '0P3', '0PD', '0PF', '0PL', '0PQ', '0PS', '0Pa', '0QR', '0Qc', '0Qt', '0Qy', 
        '0R0', '0R2', '0R3', '0R4', '0R5', '0R6', '0R7', '0R9', '0SO', '0TI', '0TR', 
        '0TT', '0TV', '0TY', '0Tt', '0UT', '0XA', '0XC', '0XU', '0Ya', '0Yg', '0Yh', 
        '0Yi', '0Yj', '0Yk', '0Yl', '0Ym', '0Yn', '0Yq', '0Ys', '0Yt', '0Yu', '0Yw', 
        '0Yz', '0Z0', '0ca', '0cs', '0e1', '0em', '0eo', '0ep', '0eq', '0f1', '0ns', 
        '0ro', '0rp', '0rs', '0sp', '0tR', '0tS', '0tn', '0ts', '100', '101', '102', 
        '110', '149', '1AJ', '1CF', '1CP', '1CS', '1EF', '1ES', '1EV', '1Ep', '1FS', 
        '1JS', '1L7', '1L8', '1RP', '1S1', '1Ya', '1Yb', '1bm', '1br', '1cb', '1ci', 
        '1cl', '1dc', '1de', '1do', '1dp', '1dr', '1gh', '1gp', '1mr', '1pm', '1ps', 
        '1rp', '1rr', '1sa', '1vc', '200', '201', '202', '203', '204', '205', '2LA', 
        '300', '301', '308', '309', '30A', '30C', '30D', '30F', '30L', '30Q', '30R', 
        '30S', '30V', '30W', '30a', '30c', '30d', '30e', '30f', '30g', '30m', '30p', 
        '30r', '30t', '30v', '310', '31A', '31C', '31S', '31V', '31c', '31d', '31i', 
        '31o', '31v', '3J5', '3M0', '3M1', '3M2', '3M3', '3M4', '3M5', '3M6', '3M7', 
        '3M8', '3M9', '3MA', '3MB', '3MC', '3MD', '3ME', '3MF', '3MG', '3MH', '3MI', 
        '3MJ', '3MK', '3ML', '3MM', '3MN', '3MO', '3MP', '3MQ', '3MR', '3MS', '3MT', 
        '3MU', '3MV', '3MW', '3MX', '3MY', '3MZ', '3N0', '3N1', '3N2', '3N3', '3NA', 
        '3NO', '3NP', '3NS', '3NT', '3NU', '3NV', '3NW', '3NX', '3NY', '3NZ', '3SP', 
        '3SS', '400', '401', '402', '403', '404', '405', '406', '407', '408', '410', 
        '411', '412', '4A0', '4NA', '4ci', '4cl', '4co', '4dt', '4fe', '4fp', '4ft', 
        '4ie', '4pb', '4pv', '4sr', '4st', '4sv', '4ws', '4wt', '4xs', '551', '552', 
        '553', '554', '556', '557', '558', '559', '560', '561', '563', '572', '573', 
        '575', '576', '5Pa', '700', '707', '708', '709', '710', '711', '712', '713', 
        '714', '715', '716', '737', '754', '766', '777', '790', '7dl', '7tf', '807', 
        '80D', '822', '823', '824', '888', '918', '999', '9m0', '9m1', '9m2', '9m3', 
        '9m4', '9m5', '9m6', '9m7', '9s0', '9s1', '9s2', '9s3'
    ];

    for(var i = 0; i < setupKeyPrefixes.length; i++) {
        setupUrls["/" + setupKeyPrefixes[i]] = 1;
    }

    // Custom Metadata keyprefixes
    setupUrls["/m\w{2}$"] = 1;
    setupUrls["/m\w{15}$"] = 1;
}