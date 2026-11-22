# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# frigate - white-box tests for the cameras topic. Spliced into
# frigate_test.j via include.

func testConfigCamerasAndStats() {
    def f as Fake init startFake({
        "GET /api/config": answer(
            200,
            '{"version":"0.18-0","cameras":{"front":{"record":{"enabled":true}},"back":{"record":{"enabled":false}}}}'),
        "GET /api/stats": answer(
            200,
            '{"cameras":{"front":{"camera_fps":5.1,"process_fps":5,"detection_fps":0.0,"detection_enabled":false,"connection_quality":"excellent","reconnects_last_hour":2}},"service":{"uptime":42}}'),
        "GET /api/labels": answer(200, '["person","car"]'),
        "GET /api/labels?camera=front": answer(200, '["person"]')
    });
    def c as Client init fakeClient($f);
    testing.assertTrue(json.asBool(config($c), "/cameras/front/record/enabled"));
    testing.assertEqual(cameras($c), ["back", "front"]);
    testing.assertEqual(json.asInt(stats($c), "/service/uptime"), 42);
    def s as list of CameraStats init cameraStats($c);
    testing.assertEqual(len($s), 1);
    testing.assertEqual($s[0].name, "front");
    testing.assertEqual($s[0].cameraFps, 5.1);
    testing.assertEqual($s[0].processFps, 5.0);
    testing.assertEqual($s[0].detectionFps, 0.0);
    testing.assertFalse($s[0].detectionEnabled);
    testing.assertEqual($s[0].connection, "excellent");
    testing.assertEqual($s[0].reconnects, 2);
    testing.assertEqual(labels($c, ""), ["car", "person"]);
    testing.assertEqual(labels($c, "front"), ["person"]);
    stopFake($f);
    def g as Fake init startFake({"GET /api/config": answer(200, '{"version":"0.18-0"}')});
    try {
        cameras(fakeClient($g));
        missed("a config without cameras");
    } catch (e) {
        testing.assertEqual($e.message, "frigate: config: the server returned no cameras");
    }
    stopFake($g);
}

func testLatestFrame() {
    def f as Fake init startFake({
        "GET /api/front/latest.jpg": "200\nContent-Type: image/jpeg\n\nJPG",
        "GET /api/front/latest.webp?height=240": "200\nContent-Type: image/webp\n\nWEBP"
    });
    def c as Client init fakeClient($f);
    testing.assertEqual(encoding.decode("utf-8", latestFrame($c, "front", "jpg", 0)), "JPG");
    testing.assertEqual(encoding.decode("utf-8", latestFrame($c, "front", "webp", 240)), "WEBP");
    try {
        latestFrame($c, "*", "jpg", 0);
        missed("all cameras");
    } catch (e) {
        testing.assertContains($e.message, "a camera is 1 to 64 letters");
    }
    stopFake($f);
}

func testSwitchesAndRestart() {
    def f as Fake init startFake({
        "PUT /api/camera/front/set/detect": answer(200, '{"success":true}'),
        "PUT /api/camera/*/set/recordings": answer(200, '{"success":true}'),
        "PUT /api/camera/front/set/zone/porch": answer(200, '{"success":true}'),
        "PUT /api/camera/front/set/bogus": answer(
            400,
            '{"success":false,"message":"Unknown feature: bogus"}'),
        "POST /api/restart": answer(
            200,
            '{"success":true,"message":"Restarting (just wait a couple of seconds)..."}')
    });
    def c as Client init fakeClient($f);
    switchCamera($c, "front", "detect", false);
    switchCamera($c, "*", "recordings", true);
    switchPart($c, "front", "zone", "porch", true);
    restart($c);
    for (def bad in ["bogus", "birdseye_mode", "profile"]) {
        try {
            switchCamera($c, "front", $bad, true);
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "a camera feature is one of enabled, detect");
        }
    }
    try {
        switchPart($c, "*", "zone", "porch", true);
        missed("a part of all cameras");
    } catch (e) {
        testing.assertContains($e.message, "a camera is 1 to 64 letters");
    }
    try {
        switchPart($c, "front", "mask", "porch", true);
        missed("a bad part");
    } catch (e) {
        testing.assertContains($e.message, "a camera part is zone, motion_mask or object_mask");
    }
    try {
        switchPart($c, "front", "zone", "../x", true);
        missed("a bad zone");
    } catch (e) {
        testing.assertContains($e.message, "a zone or mask name is");
    }
    def seen as list of string init stopFake($f);
    testing.assertTrue(strings.startsWith(
        $seen[0],
        "PUT /api/camera/front/set/detect|Content-Type=application/json|"));
    testing.assertTrue(strings.endsWith($seen[0], '|{"value":"OFF"}'));
    testing.assertTrue(strings.startsWith($seen[1], "PUT /api/camera/*/set/recordings|"));
    testing.assertTrue(strings.endsWith($seen[1], '|{"value":"ON"}'));
    testing.assertTrue(strings.startsWith($seen[2], "PUT /api/camera/front/set/zone/porch|"));
    testing.assertTrue(strings.startsWith($seen[3], "POST /api/restart|Authorization="));
    testing.assertEqual(len($seen), 4);
}
