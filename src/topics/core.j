# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# frigate - core: the client and its settings, signing in, the HTTP exchange
# with its deadline and caps, errors, JSON readers, the server version and
# user, and `call` / `fetch`. Spliced into frigate.j via include.

/** How long one request may take, in milliseconds: 30 seconds. */
export def const DEFAULT_TIMEOUT_MS as int init 30000;

/** The largest JSON response read, in bytes: 16 MiB. */
export def const DEFAULT_MAX_BYTES as int init 16777216;

/** The largest image or video read, in bytes: 256 MiB. */
export def const DEFAULT_MAX_MEDIA_BYTES as int init 268435456;

# what an error message never shows: control characters and the bidi controls
# that reorder a terminal line
def const UNSHOWN as string init '[\x00-\x1f\x7f-\x9f\x{061c}\x{200b}-\x{200f}\x{2028}-\x{202e}\x{2060}-\x{2069}\x{feff}]';

# a query parameter name: Frigate's are snake_case
def const PARAM as string init '^[a-z][a-z0-9_]*$';

# a camera, zone or mask name, or a label: what Frigate allows in its config
def const NAME as string init '^[A-Za-z0-9_-]{1,64}$';

# an event or review item id: `<unix time>-<random suffix>`
def const ITEM_ID as string init '^[0-9]{1,12}(\.[0-9]{1,9})?-[a-z0-9]{1,16}$';

# a JWT as Frigate issues it: three base64url parts
def const TOKEN_FORM as string init '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$';

# the longest token accepted
def const MAX_TOKEN as int init 4096;

# the hosts plain http is allowed to without `withPlainHttp`
def const LOOPBACK as list of string init ["127.0.0.1", "localhost", "[::1]"];

/**
 * How to reach a Frigate server and who is asking. Build it with `client`,
 * sign in with `login` or `withToken`, change it with the `with*`
 * functions.
 *
 * @field baseUrl {string} the server's URL without a trailing slash and without `/api`, such as `https://nvr.example.org:8971`
 * @field token {string} the JWT sent as a bearer token, `""` when not signed in (the unauthenticated port 5000 needs none)
 * @field tls {http.TlsOptions} certificate checks for an `https` URL
 * @field allowPlainHttp {bool} whether plain `http` to another machine is allowed (the password and token then cross the network in clear)
 * @field timeoutMs {int} how long one request may take
 * @field maxBytes {int} the largest JSON response read
 * @field maxMediaBytes {int} the largest image or video read
 */
export def struct Client {
    baseUrl as string,
    token as string,
    tls as http.TlsOptions,
    allowPlainHttp as bool,
    timeoutMs as int,
    maxBytes as int,
    maxMediaBytes as int
};

/**
 * Who the client is signed in as.
 *
 * @field username {string} the user name; `anonymous` on the unauthenticated port
 * @field role {string} `admin`, `viewer` or a custom role
 * @field cameras {list of string} the cameras the user may see
 */
export def struct Profile {
    username as string,
    role as string,
    cameras as list of string
};

/**
 * Throw a frigate error.
 *
 * @param message {string} what went wrong, without the `frigate: ` prefix
 * @throws {Error} kind "frigate", always
 */
func fail(message as string) {
    throw Error{kind: "frigate", message: "frigate: " + $message};
}

/**
 * Throw a reached cap: kind "limit", the message as `fail` writes it.
 *
 * @param message {string} what was over the cap, without the `frigate: ` prefix
 * @throws {Error} kind "limit", always
 */
func failLimit(message as string) {
    throw Error{kind: "limit", message: "frigate: " + $message};
}

/**
 * Throw a deadline that passed: kind "timeout", the message as `fail`
 * writes it.
 *
 * @param message {string} what took too long, without the `frigate: ` prefix
 * @throws {Error} kind "timeout", always
 */
func failTimeout(message as string) {
    throw Error{kind: "timeout", message: "frigate: " + $message};
}

/**
 * A request the server refused: its status is not 2xx.
 *
 * @field kind {string} always "frigate.http"
 * @field message {string} `frigate: <request>: <why> (HTTP nnn)`
 * @field status {int} the HTTP status, such as 401, 404 or 422
 * @field fields {map of string to string} the validation errors of a 422 answer, `<where>.<name>` (such as `query.limit` or `body.subLabel`) -> its message; empty otherwise
 */
export def struct HttpError {
    kind as string,
    message as string,
    status as int,
    fields as map of string to string
};

/**
 * Throw the HttpError of a refused request.
 *
 * @param what {string} the request, for the message
 * @param why {string} the explanation
 * @param status {int} the HTTP status
 * @param fields {map of string to string} the validation errors
 * @throws {HttpError} kind "frigate.http", always
 */
func failHttp(what as string, why as string, status as int, fields as map of string to string) {
    throw HttpError{
        kind: "frigate.http",
        message: io.sprintf("frigate: %s: %s (HTTP %d)", $what, cleaned($why, 500), $status),
        status: $status,
        fields: $fields
    };
}

/**
 * Server-controlled text made safe for a message: control and bidi
 * characters as `?`, at most a number of characters.
 *
 * @param s {string} the text
 * @param most {int} the most characters kept
 * @return {string} the text
 */
func cleaned(s as string, most as int) {
    def text as string init $s;
    if (len($text) > $most) {
        $text = $text[..$most] + "...";
    }
    return regex.replace(UNSHOWN, $text, "?");
}

/**
 * Text quoted for an error message.
 *
 * @param s {string} the text
 * @return {string} the text in double quotes, cleaned and cut at 200 characters
 */
func shown(s as string) {
    return "\"" + cleaned($s, 200) + "\"";
}

/**
 * Refuse an int outside a range.
 *
 * @param value {int} the value
 * @param low {int} the smallest allowed
 * @param high {int} the largest allowed
 * @param what {string} what the value is
 */
func checkRange(value as int, low as int, high as int, what as string) {
    if ($value < $low or $value > $high) {
        fail(io.sprintf("%s must be %d to %d, got %d", $what, $low, $high, $value));
    }
}

/**
 * Refuse a camera, zone or mask name, or a label, that Frigate would not
 * accept.
 *
 * @param name {string} the name
 * @param what {string} what it is
 */
func checkName(name as string, what as string) {
    if (not regex.matches(NAME, $name)) {
        fail($what + " is 1 to 64 letters, digits, _ and -, got " + shown($name));
    }
}

/**
 * Refuse an event or review item id of the wrong form.
 *
 * @param id {string} the id
 * @param what {string} what it is
 */
func checkItemId(id as string, what as string) {
    if (not regex.matches(ITEM_ID, $id)) {
        fail($what + " is <unix time>-<suffix>, such as 1794646971.714268-8qyqhn, got " + shown($id));
    }
}

/**
 * Refuse a time that is not a Unix time in seconds after 1970 and before
 * the year 5000.
 *
 * @param t {float} the time
 * @param what {string} what it is
 */
func checkTime(t as float, what as string) {
    if ($t < 0.0 or $t > 95617584000.0) {
        fail($what + " is Unix seconds, 0 or later, got " + io.sprintf("%f|prec=3", $t));
    }
}

/**
 * A Unix time for a URL: the digits, up to six decimals, no trailing
 * zeros.
 *
 * @param t {float} the time
 * @return {string} such as `1794646966.714268` or `1794646944`
 */
func stamp(t as float) {
    def s as string init io.sprintf("%f|prec=6", $t);
    while (strings.endsWith($s, "0")) {
        $s = $s[..len($s) - 1];
    }
    if (strings.endsWith($s, ".")) {
        $s = $s[..len($s) - 1];
    }
    return $s;
}

/**
 * A client for a Frigate server, not signed in. The URL is the server's
 * root: port 8971 serves the API over https with sign-in, port 5000 over
 * plain http without (only reachable where the operator published it).
 * Plain `http` to another machine is refused when a request is sent: add
 * `withPlainHttp` for a server on the LAN.
 *
 * @param baseUrl {string} the server's URL, such as `https://nvr.example.org:8971` or `http://localhost:5000`
 * @return {Client} the client
 * @throws {Error} kind "frigate" when the URL is not an absolute http(s) URL without query or fragment, or ends in `/api`
 * @example
 *   def c as frigate.Client init frigate.client("https://nvr.example.org:8971");
 */
export func client(baseUrl as string) {
    def base as string init $baseUrl;
    while (strings.endsWith($base, "/")) {
        $base = $base[..len($base) - 1];
    }
    def c as Client init Client{
        baseUrl: $base,
        token: "",
        tls: http.TlsOptions{},
        allowPlainHttp: false,
        timeoutMs: DEFAULT_TIMEOUT_MS,
        maxBytes: DEFAULT_MAX_BYTES,
        maxMediaBytes: DEFAULT_MAX_MEDIA_BYTES
    };
    checkUrlForm($c.baseUrl);
    return $c;
}

/**
 * Refuse a base URL that is not absolute http(s), has a query or fragment,
 * or ends in `/api`.
 *
 * @param baseUrl {string} the URL, without a trailing slash
 * @return {regex.Match} the URL's parts: scheme, host, port
 */
func checkUrlForm(baseUrl as string) {
    def m as regex.Match init regex.find(
        '^(https?)://(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*)(:([0-9]{1,5}))?(/[A-Za-z0-9._~-]+)*/?$',
        $baseUrl);
    if ($m.start < 0 or regex.matches('/\.+(/|$)', $baseUrl) or
        ($m.groups[6] != "" and
        (convert.toInt($m.groups[6]) < 1 or convert.toInt($m.groups[6]) > 65535))) {
        fail("a base URL is http(s)://host[:port][/path], port 1 to 65535, the path plain segments, got " +
            shown($baseUrl));
    }
    if (strings.endsWith($baseUrl, "/api")) {
        fail("the base URL is the server's root, without /api: got " + shown($baseUrl));
    }
    return $m;
}

/**
 * Refuse a base URL `checkUrlForm` refuses, or plain http to another
 * machine without `allowPlainHttp`.
 *
 * @param c {Client} the client
 */
func checkUrl(c as Client) {
    def m as regex.Match init checkUrlForm($c.baseUrl);
    if ($m.groups[0] == "http" and not $c.allowPlainHttp and
        not lists.contains(LOOPBACK, strings.lower($m.groups[1]))) {
        fail("plain http to " + shown($m.groups[1]) +
            " would send the password and token in clear: use https, or withPlainHttp");
    }
}

/**
 * The client allowed to use plain `http` to another machine, such as the
 * unauthenticated port 5000 on the LAN. A password and token cross the
 * network in clear.
 *
 * @param c {Client} the client
 * @return {Client} the client
 */
export func withPlainHttp(c as Client) {
    $c.allowPlainHttp = true;
    return $c;
}

/**
 * The client signed in with a JWT that `login` returned earlier (in
 * `Client.token`) or that the Frigate UI set as its `frigate_token`
 * cookie. It works until it expires: the server's `auth.session_length`,
 * 24 hours by default.
 *
 * @param c {Client} the client
 * @param token {string} the token
 * @return {Client} the client
 * @throws {Error} kind "frigate" when the token is not a JWT
 * @example
 *   $c = frigate.withToken($c, os.getEnv("FRIGATE_TOKEN"));
 */
export func withToken(c as Client, token as string) {
    if (len($token) > MAX_TOKEN or not regex.matches(TOKEN_FORM, $token)) {
        fail("a token is a JWT: three base64url parts joined by dots");
    }
    $c.token = $token;
    return $c;
}

/**
 * The client with certificate options for `https`: `caCert` for a
 * certificate from a private CA. Port 8971 serves Frigate's own
 * certificate until the operator installs one; it names no host (`CN=*`,
 * no subject alternative names), so no client can verify it, and only
 * `skipVerify` reaches it.
 *
 * @param c {Client} the client
 * @param tls {http.TlsOptions} the options (`caCert`, `skipVerify`)
 * @return {Client} the client
 */
export func withTls(c as Client, tls as http.TlsOptions) {
    $c.tls = $tls;
    return $c;
}

/**
 * The client with another deadline for each request.
 *
 * @param c {Client} the client
 * @param ms {int} 1000 to 86400000 milliseconds
 * @return {Client} the client
 */
export func withTimeout(c as Client, ms as int) {
    checkRange($ms, 1000, 86400000, "the timeout");
    $c.timeoutMs = $ms;
    return $c;
}

/**
 * The client with another cap on JSON responses.
 *
 * @param c {Client} the client
 * @param most {int} 65536 to 268435456 bytes
 * @return {Client} the client
 */
export func withMaxBytes(c as Client, most as int) {
    checkRange($most, 65536, 268435456, "the largest response");
    $c.maxBytes = $most;
    return $c;
}

/**
 * The client with another cap on images and videos (snapshots, clips,
 * exports).
 *
 * @param c {Client} the client
 * @param most {int} 65536 to 2147483647 bytes
 * @return {Client} the client
 */
export func withMaxMediaBytes(c as Client, most as int) {
    checkRange($most, 65536, 2147483647, "the largest image or video");
    $c.maxMediaBytes = $most;
    return $c;
}

/**
 * A query string from `name=value` parameters, each value percent-encoded.
 *
 * @param query {list of string} the parameters, such as `cameras=front`
 * @return {string} `?a=b&c=d`, or `""` without parameters
 */
func queryOf(query as list of string) {
    if (len($query) == 0) {
        return "";
    }
    def parts as list of string init [];
    for (def q in $query) {
        def at as int init strings.indexOf($q, "=");
        if ($at < 1 or not regex.matches(PARAM, $q[..$at])) {
            fail("a query parameter is name=value with a snake_case name such as has_clip, got " +
                shown($q));
        }
        $parts[] = $q[..$at] + "=" + uri.encode($q[$at + 1..]);
    }
    return "?" + strings.join($parts, "&");
}

/**
 * Whether a query sets a parameter.
 *
 * @param query {list of string} the parameters
 * @param name {string} the name
 * @return {bool} true when one of them is `name=...`
 */
func hasParam(query as list of string, name as string) {
    for (def q in $query) {
        if (strings.startsWith($q, $name + "=")) {
            return true;
        }
    }
    return false;
}

/**
 * Send one request within the deadline.
 *
 * @param c {Client} the client
 * @param method {string} the HTTP method
 * @param path {string} the path and query below the base URL, starting with `/`
 * @param body {string} a JSON body, `""` for none
 * @param maxBytes {int} the largest response read
 * @param what {string} the request, for messages
 * @return {http.BytesResponse} the response, any status
 */
func exchange(
    c as Client,
    method as string,
    path as string,
    body as string,
    maxBytes as int,
    what as string) {
    checkUrl($c);
    def headers as map of string to string init {"Accept": "application/json"};
    if ($c.token != "") {
        if (len($c.token) > MAX_TOKEN or not regex.matches(TOKEN_FORM, $c.token)) {
            fail("the client's token was changed to something that is not a JWT");
        }
        $headers["Authorization"] = "Bearer " + $c.token;
    }
    if ($body != "") {
        $headers["Content-Type"] = "application/json";
    }
    def url as string init $c.baseUrl + $path;
    def timeoutMs as int init $c.timeoutMs;
    def tls as http.TlsOptions init $c.tls;
    def t as task of http.BytesResponse init spawn {
        return http.requestWithBytes($method, $url, $headers, $body, $timeoutMs, $maxBytes, $tls);
    };
    try {
        return task.waitTimeout($t, $timeoutMs);
    } catch (e) {
        # A cancel is kind "cancelled" (jennifer after 0.25); the message
        # match is for older interpreters and goes with the next floor raise.
        if ($e.kind == "cancelled" or $e.message == "task cancelled") {
            task.cancel($t);
            task.discard($t);
            throw $e;
        }
        if ($e.kind == "timeout") {
            task.cancel($t);
            task.discard($t);
            failTimeout(io.sprintf("%s: no answer within %d ms", $what, $timeoutMs));
        }
        # A cap is kind "limit" (jennifer after 0.25: http, net); the message
        # match is for older interpreters and goes with the next floor raise.
        if ($e.kind == "limit" or
            (strings.startsWith($e.message, "http: ") and strings.contains($e.message, " exceed"))) {
            failLimit(io.sprintf("%s: the response is over %d bytes", $what, $maxBytes));
        }
        # the server closed the connection mid-answer: a generic kind, passed on
        if ($e.kind == "closed") {
            throw Error{
                kind: "closed",
                message: "frigate: " + $what + ": the server closed the connection: " +
                    cleaned($e.message, 300)
            };
        }
        fail($what + ": cannot reach " + shown($c.baseUrl) + ": " + cleaned($e.message, 300));
    }
}

/**
 * Send an API request and read the JSON response, failing on a status that
 * is not 2xx.
 *
 * @param c {Client} the client
 * @param method {string} the HTTP method
 * @param path {string} the path and query below `/api`, starting with `/`
 * @param body {string} a JSON body, `""` for none
 * @param what {string} the request, for messages
 * @return {json.Value} the response, JSON `null` when it has no body
 */
func request(c as Client, method as string, path as string, body as string, what as string) {
    def r as http.BytesResponse init exchange(
        $c,
        $method,
        "/api" + $path,
        $body,
        $c.maxBytes,
        $what);
    checkStatus($r, $what);
    return jsonBody($r, $what);
}

/**
 * Send a request and fail when Frigate's `{success, message}` answer says
 * it did not succeed, even with a 2xx status.
 *
 * @param c {Client} the client
 * @param method {string} the HTTP method
 * @param path {string} the path and query below `/api`
 * @param body {string} a JSON body, `""` for none
 * @param what {string} the request, for messages
 * @return {json.Value} the response
 */
func command(c as Client, method as string, path as string, body as string, what as string) {
    def v as json.Value init request($c, $method, $path, $body, $what);
    if (json.typeOf($v, "/success") == "bool" and not json.asBool($v, "/success")) {
        def why as string init "the server did not do it";
        if (json.typeOf($v, "/message") == "string") {
            $why = $why + ": " + cleaned(json.asString($v, "/message"), 300);
        }
        fail($what + ": " + $why);
    }
    return $v;
}

/**
 * Read an image or video, failing on a status that is not 2xx.
 *
 * @param c {Client} the client
 * @param path {string} the path and query below the base URL, starting with `/`
 * @param what {string} the request, for messages
 * @return {bytes} the body
 */
func media(c as Client, path as string, what as string) {
    def r as http.BytesResponse init exchange($c, "GET", $path, "", $c.maxMediaBytes, $what);
    checkStatus($r, $what);
    def type as string init "";
    if (maps.has($r.headers, "content-type")) {
        $type = strings.lower($r.headers["content-type"]);
    }
    if (strings.startsWith($type, "application/json") or strings.startsWith($type, "text/html")) {
        fail($what + ": the server sent " + shown($type) + " instead of an image or video");
    }
    return $r.body;
}

/**
 * A response body as JSON.
 *
 * @param r {http.BytesResponse} the response
 * @param what {string} the request, for messages
 * @return {json.Value} the body, JSON `null` when empty
 */
func jsonBody(r as http.BytesResponse, what as string) {
    def text as string init "";
    try {
        $text = convert.stringFromBytes("utf-8", $r.body);
    } catch (e) {
        fail($what + ": the response is not UTF-8");
    }
    if (strings.trim($text) == "") {
        return json.decode("null");
    }
    try {
        return json.decode($text);
    } catch (e) {
        fail($what + ": the response is not JSON: " + shown($text));
    }
}

/**
 * Fail on a status that is not 2xx, with the server's explanation.
 *
 * @param r {http.BytesResponse} the response
 * @param what {string} the request, for messages
 */
func checkStatus(r as http.BytesResponse, what as string) {
    if ($r.status >= 200 and $r.status <= 299) {
        return null;
    }
    def why as string init $r.statusText;
    if ($r.status == 401) {
        $why = "not signed in, or the token is no longer valid";
    } elseif ($r.status == 403) {
        $why = "the user may not do this";
    }
    def detail as string init "";
    def fields as map of string to string init {};
    try {
        def text as string init strings.trim(convert.stringFromBytes("utf-8", $r.body));
        if ($text != "" and not strings.startsWith($text, "<")) {
            $detail = $text;
            def v as json.Value init json.decode($text);
            if (json.typeOf($v) == "string") {
                $detail = json.asString($v);
            } elseif (json.typeOf($v, "/message") == "string") {
                $detail = json.asString($v, "/message");
            } elseif (json.typeOf($v, "/detail") == "string") {
                $detail = json.asString($v, "/detail");
            } elseif (json.typeOf($v, "/detail") == "list") {
                $fields = fieldErrors($v);
                $detail = "invalid request" + fieldText($fields);
            }
        }
    } catch (e) {
        $detail = $detail;
    }
    if ($detail != "" and $detail != $why) {
        $why = $why + ": " + $detail;
    }
    failHttp($what, $why, $r.status, $fields);
}

/**
 * The field errors of a FastAPI validation answer (`detail`: a list of
 * `{loc, msg}`), each location joined with dots.
 *
 * @param v {json.Value} the answer
 * @return {map of string to string} location -> message, such as `query.limit` -> `Input should be a valid integer`
 */
func fieldErrors(v as json.Value) {
    def fields as map of string to string init {};
    for (def i in 0..json.length($v, "/detail")) {
        def at as string init "/detail/" + convert.toString($i);
        if (json.typeOf($v, $at + "/loc") != "list") {
            continue;
        }
        def parts as list of string init [];
        for (def j in 0..json.length($v, $at + "/loc")) {
            def p as string init $at + "/loc/" + convert.toString($j);
            if (json.typeOf($v, $p) == "string") {
                $parts[] = json.asString($v, $p);
            } elseif (json.typeOf($v, $p) == "int") {
                $parts[] = convert.toString(json.asInt($v, $p));
            }
        }
        def msg as string init "";
        if (json.typeOf($v, $at + "/msg") == "string") {
            $msg = json.asString($v, $at + "/msg");
        }
        $fields[cleaned(strings.join($parts, "."), 100)] = cleaned($msg, 200);
    }
    return $fields;
}

/**
 * Field errors for a message.
 *
 * @param fields {map of string to string} location -> message
 * @return {string} ` (location: message; ...)`, or `""` when there are none
 */
func fieldText(fields as map of string to string) {
    if (len($fields) == 0) {
        return "";
    }
    def parts as list of string init [];
    for (def k in $fields) {
        if ($fields[$k] == "") {
            $parts[] = $k;
        } else {
            $parts[] = $k + ": " + $fields[$k];
        }
    }
    return " (" + strings.join($parts, "; ") + ")";
}

/**
 * A string at a JSON pointer, `""` when absent or null.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {string} the string
 */
func textAt(v as json.Value, ptr as string) {
    def t as string init json.typeOf($v, $ptr);
    if ($t == "missing" or $t == "null") {
        return "";
    }
    if ($t != "string") {
        fail(shown($ptr) + " is a " + $t + ", not a string");
    }
    return json.asString($v, $ptr);
}

/**
 * An integer at a JSON pointer, 0 when absent or null.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {int} the number
 */
func intAt(v as json.Value, ptr as string) {
    def t as string init json.typeOf($v, $ptr);
    if ($t == "missing" or $t == "null") {
        return 0;
    }
    if ($t != "int") {
        fail(shown($ptr) + " is a " + $t + ", not an integer");
    }
    return json.asInt($v, $ptr);
}

/**
 * A number at a JSON pointer, integer or not, 0 when absent or null.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {float} the number
 */
func numAt(v as json.Value, ptr as string) {
    def t as string init json.typeOf($v, $ptr);
    if ($t == "missing" or $t == "null") {
        return 0.0;
    }
    if ($t == "int") {
        return convert.toFloat(json.asInt($v, $ptr));
    }
    if ($t != "float") {
        fail(shown($ptr) + " is a " + $t + ", not a number");
    }
    return json.asFloat($v, $ptr);
}

/**
 * A boolean at a JSON pointer, false when absent or null.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {bool} the value
 */
func boolAt(v as json.Value, ptr as string) {
    def t as string init json.typeOf($v, $ptr);
    if ($t == "missing" or $t == "null") {
        return false;
    }
    if ($t != "bool") {
        fail(shown($ptr) + " is a " + $t + ", not a boolean");
    }
    return json.asBool($v, $ptr);
}

/**
 * The strings of a JSON list, empty when absent or null.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {list of string} the strings
 */
func textsAt(v as json.Value, ptr as string) {
    def t as string init json.typeOf($v, $ptr);
    def out as list of string init [];
    if ($t == "missing" or $t == "null") {
        return $out;
    }
    if ($t != "list") {
        fail(shown($ptr) + " is a " + $t + ", not a list");
    }
    for (def i in 0..json.length($v, $ptr)) {
        $out[] = textAt($v, $ptr + "/" + convert.toString($i));
    }
    return $out;
}

/**
 * Refuse a response that is not a JSON list.
 *
 * @param v {json.Value} the response
 * @param what {string} the request, for messages
 * @return {int} its length
 */
func listLength(v as json.Value, what as string) {
    if (json.typeOf($v) != "list") {
        fail($what + ": the server returned a " + json.typeOf($v) + ", not a list");
    }
    return json.length($v);
}

/**
 * Sign in with a user name and password. The client then carries the JWT
 * the server set as its `frigate_token` cookie (or the cookie
 * `auth.cookie_name` names); `Client.token` holds it for `withToken` in a later
 * run. Frigate keeps no session to end: the token works until it expires
 * (`auth.session_length`, 24 hours by default), so there is no logout.
 *
 * @param c {Client} the client, usually on port 8971
 * @param username {string} the user name
 * @param password {string} the password
 * @return {Client} the signed-in client
 * @throws {HttpError} kind "frigate.http" when the server refuses the name or password (status 401), is rate limiting sign-ins (429), or another status is not 2xx
 * @throws {Error} kind "frigate" when the server cannot be reached or sends no token
 * @example
 *   $c = frigate.login($c, "admin", os.getEnv("FRIGATE_PASSWORD"));
 */
export func login(c as Client, username as string, password as string) {
    if ($username == "") {
        fail("login: the user name is empty");
    }
    $c.token = "";
    def body as json.Value init json.map({"user": $username, "password": $password});
    def what as string init "login " + shown($username);
    def r as http.BytesResponse init exchange(
        $c,
        "POST",
        "/api/login",
        json.encode($body),
        $c.maxBytes,
        $what);
    if ($r.status == 401) {
        failHttp($what, "the server refused the user name or password", 401, {});
    }
    checkStatus($r, $what);
    def cookie as string init "";
    if (maps.has($r.headers, "set-cookie")) {
        $cookie = $r.headers["set-cookie"];
    }
    def token as string init tokenCookie($cookie);
    if (len($token) > MAX_TOKEN or not regex.matches(TOKEN_FORM, $token)) {
        fail("login: the server returned a token that is not a JWT");
    }
    $c.token = $token;
    return $c;
}

/**
 * The token in a login answer's cookies: `frigate_token`, or, when the
 * operator renamed it (`auth.cookie_name`), the one cookie whose value is a
 * JWT.
 *
 * @param cookie {string} the `set-cookie` header, several cookies joined by `, `
 * @return {string} the token
 */
func tokenCookie(cookie as string) {
    def m as regex.Match init regex.find('(^|[ ,;])frigate_token=([^;, ]*)', $cookie);
    if ($m.start >= 0) {
        return $m.groups[1];
    }
    def jwts as list of string init [];
    for (def part in strings.split($cookie, ", ")) {
        def one as regex.Match init regex.find(
            '^[A-Za-z0-9_-]+=([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)(;|$)',
            $part);
        if ($one.start >= 0) {
            $jwts[] = $one.groups[0];
        }
    }
    if (len($jwts) != 1) {
        fail(io.sprintf(
            "login: the server set %d cookies holding a token, not one (is this the unauthenticated port 5000?)",
            len($jwts)));
    }
    return $jwts[0];
}

/**
 * The Frigate version, such as `0.18.2-cfa08c5`.
 *
 * @param c {Client} the client
 * @return {string} the version
 * @throws {HttpError} kind "frigate.http" when the status is not 2xx
 * @throws {Error} kind "frigate" when the request fails
 */
export func version(c as Client) {
    def r as http.BytesResponse init exchange(
        $c,
        "GET",
        "/api/version",
        "",
        $c.maxBytes,
        "version");
    checkStatus($r, "version");
    def text as string init "";
    try {
        $text = strings.trim(convert.stringFromBytes("utf-8", $r.body));
    } catch (e) {
        fail("version: the response is not UTF-8");
    }
    if (not regex.matches('^[0-9]+\.[0-9]+[A-Za-z0-9.+-]*$', $text)) {
        fail("version: the server sent no version: " + shown($text));
    }
    return $text;
}

/**
 * Who the client is signed in as, and which cameras they may see. A quick
 * check that a token still works.
 *
 * @param c {Client} the client
 * @return {Profile} the user
 * @throws {HttpError} kind "frigate.http" when not signed in (401) or the status is not 2xx
 * @throws {Error} kind "frigate" when the request fails
 */
export func profile(c as Client) {
    def v as json.Value init request($c, "GET", "/profile", "", "profile");
    if (json.typeOf($v, "/username") != "string") {
        fail("profile: the server sent no user name");
    }
    return Profile{
        username: textAt($v, "/username"),
        role: textAt($v, "/role"),
        cameras: textsAt($v, "/allowed_cameras")
    };
}

/**
 * Refuse a method or API path `call` and `fetch` would not send.
 *
 * @param method {string} the method
 * @param path {string} the path
 */
func checkCall(method as string, path as string) {
    if (not lists.contains(["GET", "POST", "PUT", "PATCH", "DELETE"], $method)) {
        fail("a method is GET, POST, PUT, PATCH or DELETE, got " + shown($method));
    }
    if (not regex.matches('^(/[A-Za-z0-9_.*-]+)+/?$', $path) or regex.matches('/\.+(/|$)', $path)) {
        fail("a path is /segments of letters, digits and _.*-, got " + shown($path));
    }
}

/**
 * Any other API request.
 *
 * @param c {Client} the client
 * @param method {string} `GET`, `POST`, `PUT`, `PATCH` or `DELETE`
 * @param path {string} the path below `/api`, such as `/timeline` or `/events/<id>/description`
 * @param query {list of string} parameters as `name=value`
 * @param body {json.Value} the body, JSON `null` for none
 * @return {json.Value} the response, JSON `null` when it has no body
 * @throws {HttpError} kind "frigate.http" when the status is not 2xx
 * @throws {Error} kind "frigate" when the method or path is malformed, or the request fails
 * @example
 *   def tl as json.Value init frigate.call($c, "GET", "/timeline", ["camera=front", "limit=20"], json.decode("null"));
 */
export func call(
    c as Client,
    method as string,
    path as string,
    query as list of string,
    body as json.Value) {
    checkCall($method, $path);
    def payload as string init "";
    if (json.typeOf($body) != "null") {
        $payload = json.encode($body);
    }
    return request($c, $method, $path + queryOf($query), $payload, $method + " " + $path);
}

/**
 * Any other image or video below `/api`, read under the media cap.
 *
 * @param c {Client} the client
 * @param path {string} the path below `/api`, such as `/front/grid.jpg` or `/review/<id>/clip.mp4`
 * @param query {list of string} parameters as `name=value`
 * @return {bytes} the body
 * @throws {HttpError} kind "frigate.http" when the status is not 2xx
 * @throws {Error} kind "limit" when it is over the client's media cap; kind "frigate" when the path is malformed, the server sends JSON or HTML, or the request fails
 * @example
 *   def grid as bytes init frigate.fetch($c, "/front/grid.jpg", []);
 */
export func fetch(c as Client, path as string, query as list of string) {
    checkCall("GET", $path);
    return media($c, "/api" + $path + queryOf($query), "GET " + $path);
}
