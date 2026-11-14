# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# frigate - white-box tests for the core topic, and the fake server the
# other overlays use. Spliced into frigate_test.j via include.

# a JWT for the fake: header, payload and signature in base64url
def const TOKEN as string init "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhZG1pbiIsInJvbGUiOiJhZG1pbiJ9.c2lnbmF0dXJlLXRoYXQtaXMtZmFrZQ";

# an event and a review item id
def const EVENT as string init "1794646971.714268-8qyqhn";
def const REVIEW as string init "1794646971.714268-w3d0pb";

/**
 * A running fake Frigate server.
 *
 * @field srv {httpd.Server} the server
 * @field base {string} its base URL
 * @field t {task of list of string} the task serving it; its result is every request seen
 */
def struct Fake {
    srv as httpd.Server,
    base as string,
    t as task of list of string
};

/**
 * Mark a call that should have thrown.
 *
 * @param what {string} what got through
 * @throws {Error} always, kind "missed"
 */
func missed(what as string) {
    throw Error{kind: "missed", message: $what};
}

/**
 * Start a fake Frigate server. An answer is looked up by `METHOD path?query`,
 * then `METHOD path`; it is the status, a newline, header lines `Name: value`,
 * an empty line and the body. A request with no answer gets 404 and
 * `{"success": false, "message": ...}`; an answer whose status is `SLEEP`
 * waits 3 seconds.
 *
 * @param answers {map of string to string} the answers
 * @return {Fake} the server
 */
func startFake(answers as map of string to string) {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    def base as string init "http://" + httpd.address($srv);
    def t as task of list of string init spawn {
        return serveFake($srv, $answers);
    };
    return Fake{srv: $srv, base: $base, t: $t};
}

/**
 * Serve requests until the server shuts down.
 *
 * @param srv {httpd.Server} the server
 * @param answers {map of string to string} the answers
 * @return {list of string} each request as `METHOD path?query|header=value|...|body`
 */
func serveFake(srv as httpd.Server, answers as map of string to string) {
    def seen as list of string init [];
    while (true) {
        def req as httpd.Request;
        try {
            $req = httpd.accept($srv);
        } catch (e) {
            return $seen;
        }
        def target as string init httpd.path($req);
        if (httpd.rawQuery($req) != "") {
            $target = $target + "?" + httpd.rawQuery($req);
        }
        def key as string init httpd.method($req) + " " + $target;
        def line as list of string init [$key];
        for (def h in ["Content-Type", "Authorization"]) {
            if (httpd.header($req, $h) != "") {
                $line[] = $h + "=" + httpd.header($req, $h);
            }
        }
        $line[] = convert.stringFromBytes("utf-8", httpd.body($req));
        $seen[] = strings.join($line, "|");
        def spec as string init "404\nContent-Type: application/json\n\n" +
            '{"success":false,"message":"no answer for ' + $key + '"}';
        if (maps.has($answers, $key)) {
            $spec = $answers[$key];
        } elseif (maps.has($answers, httpd.method($req) + " " + httpd.path($req))) {
            $spec = $answers[httpd.method($req) + " " + httpd.path($req)];
        }
        def split as int init strings.indexOf($spec, "\n\n");
        def head as list of string init strings.split($spec[..$split], "\n");
        for (def h in $head[1..]) {
            def at as int init strings.indexOf($h, ": ");
            httpd.setHeader($req, $h[..$at], $h[$at + 2..]);
        }
        if ($head[0] == "SLEEP") {
            time.sleep(time.fromMilliseconds(3000));
            httpd.respond($req, 200, '{}');
        } else {
            httpd.respond($req, convert.toInt($head[0]), $spec[$split + 2..]);
        }
    }
}

/**
 * Stop a fake and return what it saw.
 *
 * @param f {Fake} the fake
 * @return {list of string} the requests
 */
func stopFake(f as Fake) {
    httpd.shutdown($f.srv);
    return task.wait($f.t);
}

/**
 * A client of a fake, signed in with TOKEN.
 *
 * @param f {Fake} the fake
 * @return {Client} the client
 */
func fakeClient(f as Fake) {
    return withToken(client($f.base), TOKEN);
}

/**
 * A JSON answer.
 *
 * @param status {int} the status
 * @param body {string} the JSON
 * @return {string} the answer for `startFake`
 */
func answer(status as int, body as string) {
    return convert.toString($status) + "\nContent-Type: application/json\n\n" + $body;
}

func testClientUrlsAndSettings() {
    def c as Client init client("https://nvr.example.org:8971/");
    testing.assertEqual($c.baseUrl, "https://nvr.example.org:8971");
    testing.assertEqual($c.token, "");
    testing.assertEqual($c.maxMediaBytes, DEFAULT_MAX_MEDIA_BYTES);
    for (def bad in [
        "ftp://x",
        "https://x/?a=1",
        "nvr.example.org",
        "https://x/#f",
        "https://x:0",
        "https://x:70000",
        "https://x/a/../b"
    ]) {
        try {
            client($bad);
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "a base URL is");
            testing.assertEqual($e.kind, "frigate");
        }
    }
    try {
        client("https://nvr.example.org:8971/api");
        missed("a base URL with /api");
    } catch (e) {
        testing.assertContains($e.message, "the server's root, without /api");
    }
    try {
        client("http://nvr.lan:5000");
        missed("plain http to the LAN");
    } catch (e) {
        testing.assertContains($e.message, "in clear: use https, or withPlainHttp");
    }
    testing.assertEqual(client("http://localhost:5000").baseUrl, "http://localhost:5000");
    def lan as Client init client("https://nvr.lan:5000");
    $lan.baseUrl = "http://nvr.lan:5000";
    checkUrl(withPlainHttp($lan));
    testing.assertEqual(withTimeout($c, 5000).timeoutMs, 5000);
    testing.assertEqual(withMaxBytes($c, 65536).maxBytes, 65536);
    testing.assertEqual(withMaxMediaBytes($c, 1048576).maxMediaBytes, 1048576);
    testing.assertTrue(withTls($c, http.TlsOptions{skipVerify: true}).tls.skipVerify);
    for (def bad in [999, 86400001]) {
        try {
            withTimeout($c, $bad);
            missed(convert.toString($bad));
        } catch (e) {
            testing.assertContains($e.message, "the timeout must be 1000 to 86400000");
        }
    }
    try {
        withMaxBytes($c, 1024);
        missed("a small cap");
    } catch (e) {
        testing.assertContains($e.message, "the largest response must be");
    }
    try {
        withMaxMediaBytes($c, 1024);
        missed("a small media cap");
    } catch (e) {
        testing.assertContains($e.message, "the largest image or video must be");
    }
    for (def bad in ["short", "a.b", "a.b.c d", "a.b.c.d", "a+b.c.d"]) {
        try {
            withToken($c, $bad);
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "a token is a JWT");
        }
    }
    testing.assertEqual(withToken($c, TOKEN).token, TOKEN);
}

func testStampsNamesAndQueries() {
    testing.assertEqual(stamp(1794646966.714268), "1794646966.714268");
    testing.assertEqual(stamp(1794646944.0), "1794646944");
    testing.assertEqual(stamp(0.5), "0.5");
    testing.assertEqual(stamp(0.0), "0");
    for (def bad in [-1.0, 1.0e12]) {
        try {
            checkTime($bad, "the start");
            missed("a time out of range");
        } catch (e) {
            testing.assertContains($e.message, "the start is Unix seconds");
        }
    }
    checkName("front_door-2", "a camera");
    for (def bad in ["", "front door", "a/b", "../x", strings.repeat("x", 65)]) {
        try {
            checkName($bad, "a camera");
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "a camera is 1 to 64 letters");
        }
    }
    checkItemId(EVENT, "an event id");
    checkItemId("1794646944-abc123", "an event id");
    for (def bad in ["", "abc", "1.2.3-x", "1794646971.714268-ABC", "1794646971.714268-a/b"]) {
        try {
            checkItemId($bad, "an event id");
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "an event id is <unix time>-<suffix>");
        }
    }
    testing.assertEqual(queryOf([]), "");
    testing.assertEqual(
        queryOf(["cameras=front,back", "sub_labels=a b&c"]),
        "?cameras=front%2Cback&sub_labels=a%20b%26c");
    for (def bad in ["limit", "=5", "Limit=5", "a b=1"]) {
        try {
            queryOf([$bad]);
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "a query parameter is name=value");
        }
    }
    testing.assertTrue(hasParam(["a=1", "include_thumbnails=1"], "include_thumbnails"));
    testing.assertFalse(hasParam(["include_thumbnailsx=1"], "include_thumbnails"));
}

func testLoginTakesTheCookie() {
    def f as Fake init startFake({
        "POST /api/login": "200\nSet-Cookie: frigate_token=" + TOKEN +
            "; HttpOnly; Max-Age=86400; Path=/; SameSite=lax\n\n",
        "GET /api/profile": answer(
            200,
            '{"username":"admin","role":"admin","allowed_cameras":["front","back"]}')
    });
    def c as Client init login(client($f.base), "admin", "s3cret");
    testing.assertEqual($c.token, TOKEN);
    def p as Profile init profile($c);
    testing.assertEqual($p.username, "admin");
    testing.assertEqual($p.role, "admin");
    testing.assertEqual($p.cameras, ["front", "back"]);
    try {
        login($c, "", "x");
        missed("no user name");
    } catch (e) {
        testing.assertContains($e.message, "the user name is empty");
    }
    def seen as list of string init stopFake($f);
    testing.assertEqual(
        $seen[0],
        'POST /api/login|Content-Type=application/json|{"user":"admin","password":"s3cret"}');
    testing.assertEqual($seen[1], "GET /api/profile|Authorization=Bearer " + TOKEN + "|");
}

func testLoginTakesARenamedCookie() {
    testing.assertEqual(
        tokenCookie("nvr_token=" + TOKEN + "; HttpOnly; Max-Age=86400; Path=/; SameSite=lax"),
        TOKEN);
    testing.assertEqual(
        tokenCookie("lang=en; Expires=Sat, 14 Nov 2026 09:03:25 GMT; Path=/, nvr_token=" + TOKEN +
            "; Path=/"),
        TOKEN);
    testing.assertEqual(tokenCookie("x=" + TOKEN + ", frigate_token=abc"), "abc");
    for (def bad in ["", "lang=en", "a=" + TOKEN + ", b=" + TOKEN]) {
        try {
            tokenCookie($bad);
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "cookies holding a token, not one");
        }
    }
}

func testLoginRefusals() {
    def f as Fake init startFake({"POST /api/login": answer(401, '{"message":"Login failed"}')});
    try {
        login(withToken(client($f.base), TOKEN), "admin", "wrong");
        missed("a refused login");
    } catch (e) {
        testing.assertEqual($e.kind, "frigate.http");
        testing.assertEqual($e.status, 401);
        testing.assertEqual(
            $e.message,
            "frigate: login \"admin\": the server refused the user name or password (HTTP 401)");
    }
    def seen as list of string init stopFake($f);
    testing.assertFalse(strings.contains($seen[0], "Authorization"));
    for (def cookie in ["", "Set-Cookie: other=1\n", "Set-Cookie: frigate_token=not-a-jwt\n"]) {
        def g as Fake init startFake({"POST /api/login": "200\n" + $cookie + "\n"});
        try {
            login(client($g.base), "admin", "x");
            missed($cookie);
        } catch (e) {
            testing.assertEqual($e.kind, "frigate");
            testing.assertContains($e.message, "frigate: login: the server");
        }
        stopFake($g);
    }
}

func testErrorBodies() {
    def f as Fake init startFake({
        "GET /api/events/" + EVENT: answer(404, '"Event not found"'),
        "GET /api/exports/x": answer(404, '{"success":false,"message":"Export not found"}'),
        "GET /api/review/" + REVIEW: answer(500, '{"detail":"database is locked"}'),
        "GET /api/events": answer(
            422,
            '{"detail":[{"type":"int_parsing","loc":["query","limit"],"msg":"Input should be a valid integer","input":"x"}]}'),
        "GET /api/config": "401\nContent-Type: text/html\n\n<html><body>401 Authorization Required</body></html>",
        "GET /api/stats": answer(403, '{"success":false,"message":"Access denied"}')
    });
    def c as Client init fakeClient($f);
    try {
        event($c, EVENT);
        missed("a 404 string");
    } catch (e) {
        testing.assertEqual($e.status, 404);
        testing.assertEqual(
            $e.message,
            "frigate: event " + EVENT + ": Not Found: Event not found (HTTP 404)");
    }
    try {
        exportInfo($c, "x");
        missed("a 404 message");
    } catch (e) {
        testing.assertContains($e.message, "Not Found: Export not found (HTTP 404)");
    }
    try {
        review($c, REVIEW);
        missed("a 500 detail");
    } catch (e) {
        testing.assertEqual($e.status, 500);
        testing.assertContains($e.message, ": database is locked (HTTP 500)");
    }
    try {
        events($c, ["limit=x"]);
        missed("a 422");
    } catch (e) {
        testing.assertEqual($e.kind, "frigate.http");
        testing.assertEqual($e.status, 422);
        testing.assertEqual($e.fields, {"query.limit": "Input should be a valid integer"});
        testing.assertContains(
            $e.message,
            "invalid request (query.limit: Input should be a valid integer) (HTTP 422)");
    }
    try {
        config($c);
        missed("a 401");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "frigate: config: not signed in, or the token is no longer valid (HTTP 401)");
    }
    try {
        stats($c);
        missed("a 403");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "frigate: stats: the user may not do this: Access denied (HTTP 403)");
    }
    stopFake($f);
}

func testCommandsThatDidNotSucceed() {
    def f as Fake init startFake({
        "PUT /api/camera/front/set/detect": answer(
            200,
            '{"success":false,"message":"camera is\u0007 off"}')
    });
    try {
        switchCamera(fakeClient($f), "front", "detect", true);
        missed("success false");
    } catch (e) {
        testing.assertEqual($e.kind, "frigate");
        testing.assertEqual(
            $e.message,
            "frigate: detect of \"front\": the server did not do it: camera is? off");
    }
    stopFake($f);
}

func testCallFetchAndCaps() {
    def f as Fake init startFake({
        "GET /api/timeline?camera=front&limit=2": answer(200, '[{"a":1}]'),
        "GET /api/slow": "SLEEP\n\n",
        "GET /api/big": answer(200, '{"x":"' + strings.repeat("y", 70000) + '"}'),
        "GET /api/html": "200\nContent-Type: text/html\n\n<html>",
        "GET /api/front/grid.jpg": "200\nContent-Type: image/jpeg\n\nJPEGDATA",
        "GET /api/json.jpg": answer(200, '{"success":false}'),
        "GET /api/version": "200\nContent-Type: text/plain\n\n0.18.2-cfa08c5"
    });
    def c as Client init fakeClient($f);
    testing.assertEqual(
        json.length(call($c, "GET", "/timeline", ["camera=front", "limit=2"], json.decode("null"))),
        1);
    testing.assertEqual(
        convert.stringFromBytes("utf-8", fetch($c, "/front/grid.jpg", [])),
        "JPEGDATA");
    testing.assertEqual(version($c), "0.18.2-cfa08c5");
    try {
        call(withMaxBytes($c, 65536), "GET", "/big", [], json.decode("null"));
        missed("a big response");
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
        testing.assertEqual($e.message, "frigate: GET /big: the response is over 65536 bytes");
    }
    try {
        fetch(withMaxMediaBytes($c, 65536), "/big", []);
        missed("a big image");
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
    }
    try {
        call($c, "GET", "/html", [], json.decode("null"));
        missed("not JSON");
    } catch (e) {
        testing.assertContains($e.message, "the response is not JSON");
    }
    try {
        fetch($c, "/json.jpg", []);
        missed("JSON for an image");
    } catch (e) {
        testing.assertContains($e.message, "instead of an image or video");
    }
    def started as time.Time init time.now();
    try {
        call(withTimeout($c, 1000), "GET", "/slow", [], json.decode("null"));
        missed("a slow server");
    } catch (e) {
        testing.assertEqual($e.kind, "timeout");
        testing.assertEqual($e.message, "frigate: GET /slow: no answer within 1000 ms");
    }
    testing.assertTrue(time.milliseconds(time.sub(time.now(), $started)) < 2500);
    for (def bad in [
        ["GET", "events"],
        ["GET", "/events/../config"],
        ["HEAD", "/events"],
        ["GET", "/a b"]
    ]) {
        try {
            call($c, $bad[0], $bad[1], [], json.decode("null"));
            missed($bad[1]);
        } catch (e) {
            testing.assertEqual($e.kind, "frigate");
        }
    }
    def broken as Client init $c;
    $broken.token = "x\r\nX-Evil: 1";
    try {
        call($broken, "GET", "/timeline", [], json.decode("null"));
        missed("a changed token");
    } catch (e) {
        testing.assertContains($e.message, "not a JWT");
    }
    def seen as list of string init stopFake($f);
    testing.assertEqual(
        $seen[0],
        "GET /api/timeline?camera=front&limit=2|Authorization=Bearer " + TOKEN + "|");
    try {
        version(client("http://127.0.0.1:1"));
        missed("nothing listening");
    } catch (e) {
        testing.assertEqual($e.kind, "frigate");
        testing.assertContains($e.message, "version: cannot reach");
    }
}
