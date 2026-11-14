# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# frigate - white-box tests for the recordings topic. Spliced into
# frigate_test.j via include.

# an export as `GET /exports/<id>` sent it (Frigate 0.18.2)
def const EXPORT_DONE as string init '{"id":"front_f9pg1a","camera":"front","name":"probe","date":1794646939,"video_path":"/media/frigate/exports/front_20261114_090219-20261114_090249_f9pg1a.mp4","thumb_path":"/media/frigate/clips/export/front_f9pg1a.webp","in_progress":false,"export_case":null}';

# the same export while it is written
def const EXPORT_BUSY as string init '{"id":"front_f9pg1a","camera":"front","name":"probe","date":1794646939,"video_path":"/media/frigate/exports/front_20261114_090219-20261114_090249_f9pg1a.mp4","thumb_path":"","in_progress":true,"export_case":null}';

func testRecordingsAndHours() {
    def f as Fake init startFake({
        "GET /api/front/recordings?after=1794646900&before=1794647000.5": answer(
            200,
            '[{"id":"1794646944.0-638zgj","start_time":1794646944,"end_time":1794646954,"segment_size":0.54,"motion":367,"objects":0,"duration":10.0,"motion_heatmap":{"0":19}}]'),
        "GET /api/front/recordings/summary?timezone=utc": answer(
            200,
            '[{"events":1,"hours":[{"hour":"09","events":1,"motion":2074,"objects":3,"duration":40},{"hour":"23","events":0,"motion":0,"objects":0,"duration":3600}],"day":"2026-11-14"}]'),
        "GET /api/back/recordings/summary?timezone=utc": answer(
            200,
            '[{"hours":[{"hour":"24","events":0}],"day":"2026-11-14"}]')
    });
    def c as Client init fakeClient($f);
    def recs as list of Recording init recordings($c, "front", 1794646900.0, 1794647000.5);
    testing.assertEqual(len($recs), 1);
    testing.assertEqual($recs[0].id, "1794646944.0-638zgj");
    testing.assertEqual($recs[0].startTime, 1794646944.0);
    testing.assertEqual($recs[0].endTime, 1794646954.0);
    testing.assertEqual($recs[0].duration, 10.0);
    testing.assertEqual($recs[0].motion, 367);
    testing.assertEqual($recs[0].objects, 0);
    testing.assertEqual($recs[0].sizeMb, 0.54);
    def hours as list of RecordingHour init recordingHours($c, "front");
    testing.assertEqual(len($hours), 2);
    testing.assertEqual($hours[0].day, "2026-11-14");
    testing.assertEqual($hours[0].hour, 9);
    testing.assertEqual($hours[0].events, 1);
    testing.assertEqual($hours[0].motion, 2074);
    testing.assertEqual($hours[0].objects, 3);
    testing.assertEqual($hours[0].duration, 40.0);
    testing.assertEqual($hours[1].hour, 23);
    try {
        recordingHours($c, "back");
        missed("hour 24");
    } catch (e) {
        testing.assertContains($e.message, "an hour is not 00 to 23");
    }
    for (def bad in [[100.0, 100.0], [200.0, 100.0], [0.0, 86401.0], [-5.0, 10.0]]) {
        try {
            recordings($c, "front", $bad[0], $bad[1]);
            missed(stamp($bad[0]));
        } catch (e) {
            testing.assertEqual($e.kind, "frigate");
        }
    }
    stopFake($f);
}

func testStorage() {
    def f as Fake init startFake({
        "GET /api/recordings/storage": answer(
            200,
            '{"front":{"usage":24.59,"bandwidth":0,"usage_percent":0.412},"back":{"usage":1,"bandwidth":120.5,"usage_percent":2}}')
    });
    def got as list of Storage init storage(fakeClient($f));
    testing.assertEqual(len($got), 2);
    testing.assertEqual($got[0].camera, "back");
    testing.assertEqual($got[0].bandwidthMb, 120.5);
    testing.assertEqual($got[0].usagePercent, 2.0);
    testing.assertEqual($got[1].camera, "front");
    testing.assertEqual($got[1].usageMb, 24.59);
    stopFake($f);
}

func testClipsAndFrames() {
    def f as Fake init startFake({
        "GET /api/front/start/1794646944/end/1794646964.25/clip.mp4": "200\nContent-Type: video/mp4\n\nMP4",
        "GET /api/front/recordings/1794646950/snapshot.png?height=120": "200\nContent-Type: image/png\n\nPNG",
        "GET /api/front/recordings/1794646950/snapshot.jpg": "200\nContent-Type: image/jpeg\n\nJPG",
        "GET /api/front/start/1000/end/1010/clip.mp4": answer(
            400,
            '{"success":false,"message":"No recordings found for the specified time range"}')
    });
    def c as Client init fakeClient($f);
    testing.assertEqual(
        convert.stringFromBytes("utf-8", recordingClip($c, "front", 1794646944.0, 1794646964.25)),
        "MP4");
    testing.assertEqual(
        convert.stringFromBytes("utf-8", recordingFrame($c, "front", 1794646950.0, "png", 120)),
        "PNG");
    testing.assertEqual(
        convert.stringFromBytes("utf-8", recordingFrame($c, "front", 1794646950.0, "jpg", 0)),
        "JPG");
    try {
        recordingClip($c, "front", 1000.0, 1010.0);
        missed("a 400");
    } catch (e) {
        testing.assertEqual($e.status, 400);
        testing.assertContains(
            $e.message,
            "No recordings found for the specified time range (HTTP 400)");
    }
    try {
        recordingClip($c, "front", 1000.0, 1000.0 + 86400.5);
        missed("a long clip");
    } catch (e) {
        testing.assertContains($e.message, "a time range is at most 86400 seconds");
    }
    try {
        recordingFrame($c, "front", 1.0, "png", 5000);
        missed("a tall frame");
    } catch (e) {
        testing.assertContains($e.message, "the height must be 0 to 4320");
    }
    stopFake($f);
}

func testExports() {
    def f as Fake init startFake({
        "POST /api/export/front/start/1794646939/end/1794646969": answer(
            202,
            '{"success":true,"message":"Export queued.","export_id":"front_f9pg1a","status":"queued"}'),
        "POST /api/export/back/start/1794646939/end/1794646969": answer(
            400,
            '{"success":false,"message":"No recordings found for time range"}'),
        "GET /api/exports": answer(200, "[" + EXPORT_DONE + "]"),
        "GET /api/exports/front_f9pg1a": answer(200, EXPORT_DONE),
        "GET /api/exports/busy": answer(200, EXPORT_BUSY),
        "GET /exports/front_20261114_090219-20261114_090249_f9pg1a.mp4": "200\nContent-Type: video/mp4\n\nEXPORTED",
        "POST /api/exports/delete": answer(
            200,
            '{"success":true,"message":"Successfully deleted exports."}')
    });
    def c as Client init fakeClient($f);
    testing.assertEqual(
        startExport($c, "front", 1794646939.0, 1794646969.0, "parcel"),
        "front_f9pg1a");
    startExport($c, "front", 1794646939.0, 1794646969.0, "");
    try {
        startExport($c, "back", 1794646939.0, 1794646969.0, "");
        missed("a 400");
    } catch (e) {
        testing.assertEqual($e.status, 400);
    }
    try {
        startExport($c, "front", 1.0, 2.0, strings.repeat("n", 257));
        missed("a long name");
    } catch (e) {
        testing.assertContains($e.message, "an export name is at most 256 characters");
    }
    def all as list of Export init exports($c);
    testing.assertEqual(len($all), 1);
    def e as Export init waitExport($c, "front_f9pg1a", 5000);
    testing.assertEqual($e.id, "front_f9pg1a");
    testing.assertEqual($e.camera, "front");
    testing.assertEqual($e.name, "probe");
    testing.assertEqual($e.date, 1794646939.0);
    testing.assertFalse($e.inProgress);
    testing.assertEqual(convert.stringFromBytes("utf-8", exportFile($c, $e)), "EXPORTED");
    def started as time.Time init time.now();
    try {
        waitExport($c, "busy", 1500);
        missed("an export that never finishes");
    } catch (err) {
        testing.assertEqual($err.kind, "timeout");
        testing.assertEqual(
            $err.message,
            "frigate: export busy: still being written after 1500 ms");
    }
    def took as int init time.milliseconds(time.sub(time.now(), $started));
    testing.assertTrue($took >= 1400 and $took < 3000);
    def busy as Export init exportInfo($c, "busy");
    try {
        exportFile($c, $busy);
        missed("a busy export");
    } catch (err) {
        testing.assertContains($err.message, "is still being written: waitExport first");
    }
    for (def path in [
        "/etc/passwd",
        "/media/frigate/exports/../config/frigate.db",
        "/media/frigate/exports/a/b.mp4"
    ]) {
        def odd as Export init $e;
        $odd.videoPath = $path;
        try {
            exportFile($c, $odd);
            missed($path);
        } catch (err) {
            testing.assertContains($err.message, "is not in /media/frigate/exports/");
        }
    }
    deleteExports($c, ["front_f9pg1a", "back_x1"]);
    for (def bad in [[], ["a/b"]]) {
        try {
            deleteExports($c, $bad);
            missed("bad ids");
        } catch (err) {
            testing.assertEqual($err.kind, "frigate");
        }
    }
    def seen as list of string init stopFake($f);
    testing.assertContains($seen[0], '|{"name":"parcel"}');
    testing.assertTrue(strings.endsWith($seen[1], '|{}'));
    testing.assertTrue(strings.endsWith(
        $seen[len($seen) - 1],
        '|{"ids":["front_f9pg1a","back_x1"]}'));
}
