# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# frigate - white-box tests for the events topic. Spliced into
# frigate_test.j via include.

# an event as `GET /events/<id>` sent it (Frigate 0.18.2)
def const EVENT_JSON as string init '{"id":"1794646971.714268-8qyqhn","label":"person","sub_label":"tester","camera":"front","start_time":1794646966.714268,"end_time":1794646991.714268,"false_positive":false,"zones":["porch"],"thumbnail":null,"has_clip":true,"has_snapshot":true,"retain_indefinitely":false,"plus_id":null,"model_hash":null,"detector_type":null,"model_type":null,"data":{"type":"api","score":0.9,"top_score":0.9,"snapshot_clean":true,"draw":{}}}';

# an event still tracked, as `GET /events` sent it, with an older server's
# `[label, score]` sub label
def const EVENT_OPEN as string init '{"id":"1794647400.761226-dfvti4","camera":"back","label":"doorbell","zones":[],"start_time":1794647395,"end_time":null,"has_clip":false,"has_snapshot":false,"plus_id":null,"retain_indefinitely":true,"sub_label":["carol",0.75],"top_score":0.6,"false_positive":false,"box":[],"data":{"type":"api","score":0,"top_score":0}}';

# a review item as `GET /review` sent it
def const REVIEW_JSON as string init '{"id":"1794646971.714268-w3d0pb","camera":"front","start_time":1794646971.714268,"end_time":null,"severity":"alert","thumb_path":"/media/frigate/clips/review/thumb-front-1794646971.714268-w3d0pb.webp","data":{"detections":["1794646971.714268-8qyqhn"],"objects":["person: tester"],"verified_objects":[],"sub_labels":[],"zones":["porch"],"audio":[],"thumb_time":null,"metadata":null},"has_been_reviewed":true}';

# what Frigate answers a change it made
def const DONE as string init '{"success":true,"message":"done"}';

func testEventsAndOneEvent() {
    def f as Fake init startFake({
        "GET /api/events?cameras=front&include_thumbnails=0": answer(
            200,
            "[" + EVENT_JSON + "," + EVENT_OPEN + "]"),
        "GET /api/events?include_thumbnails=1": answer(200, "[]"),
        "GET /api/events/" + EVENT: answer(200, EVENT_JSON),
        "GET /api/events?limit=1&include_thumbnails=0": answer(200, '{"not":"a list"}')
    });
    def c as Client init fakeClient($f);
    def got as list of Event init events($c, ["cameras=front"]);
    testing.assertEqual(len($got), 2);
    def ev as Event init $got[0];
    testing.assertEqual($ev.id, EVENT);
    testing.assertEqual($ev.camera, "front");
    testing.assertEqual($ev.label, "person");
    testing.assertEqual($ev.subLabel, "tester");
    testing.assertEqual($ev.score, 0.9);
    testing.assertEqual($ev.startTime, 1794646966.714268);
    testing.assertEqual($ev.endTime, 1794646991.714268);
    testing.assertFalse($ev.inProgress);
    testing.assertEqual($ev.zones, ["porch"]);
    testing.assertTrue($ev.hasClip);
    testing.assertTrue($ev.hasSnapshot);
    testing.assertFalse($ev.retained);
    testing.assertEqual(json.asString($ev.raw, "/data/type"), "api");
    def o as Event init $got[1];
    testing.assertEqual($o.subLabel, "carol");
    testing.assertEqual($o.score, 0.6);
    testing.assertEqual($o.startTime, 1794647395.0);
    testing.assertEqual($o.endTime, 0.0);
    testing.assertTrue($o.inProgress);
    testing.assertTrue($o.retained);
    testing.assertEqual(len(events($c, ["include_thumbnails=1"])), 0);
    testing.assertEqual(event($c, EVENT).label, "person");
    try {
        events($c, ["limit=1"]);
        missed("a map for a list");
    } catch (e) {
        testing.assertEqual($e.message, "frigate: events: the server returned a map, not a list");
    }
    try {
        event($c, "../config");
        missed("a path as id");
    } catch (e) {
        testing.assertContains($e.message, "an event id is");
    }
    stopFake($f);
}

func testMalformedEvents() {
    for (def bad in [
        '{"label":"x"}',
        '{"id":"../x"}',
        '[1]',
        '{"id":"' + EVENT + '","start_time":"soon"}'
    ]) {
        def f as Fake init startFake({"GET /api/events/" + EVENT: answer(200, $bad)});
        try {
            event(fakeClient($f), EVENT);
            missed($bad);
        } catch (e) {
            testing.assertEqual($e.kind, "frigate");
        }
        stopFake($f);
    }
}

func testEventChanges() {
    def f as Fake init startFake({
        "DELETE /api/events/" + EVENT: answer(200, DONE),
        "POST /api/events/" + EVENT + "/retain": answer(200, DONE),
        "DELETE /api/events/" + EVENT + "/retain": answer(200, DONE),
        "POST /api/events/" + EVENT + "/sub_label": answer(200, DONE),
        "PUT /api/events/" + EVENT + "/end": answer(200, DONE),
        "POST /api/events/front/doorbell/create": answer(
            200,
            '{"success":true,"message":"Successfully created event.","event_id":"1794647391.273952-cf67kg"}'),
        "POST /api/events/back/doorbell/create": answer(200, '{"success":true,"message":"x"}'),
        "POST /api/events/front/traffic light/create": answer(
            200,
            '{"success":true,"message":"Successfully created event.","event_id":"1794647391.273952-tl0001"}')
    });
    def c as Client init fakeClient($f);
    deleteEvent($c, EVENT);
    retainEvent($c, EVENT, true);
    retainEvent($c, EVENT, false);
    setSubLabel($c, EVENT, "alice", 0.8);
    setSubLabel($c, EVENT, "", 0.0);
    endEvent($c, EVENT);
    testing.assertEqual(createEvent($c, "front", "doorbell", "", 30), "1794647391.273952-cf67kg");
    createEvent($c, "front", "doorbell", "ring \"1\"", 0);
    try {
        createEvent($c, "back", "doorbell", "", 0);
        missed("no event id");
    } catch (e) {
        testing.assertContains($e.message, "the server returned no event id");
    }
    # a COCO label such as "traffic light" has a space; the httpd fake sees
    # the path decoded, eventPath shows it is sent encoded
    testing.assertEqual(
        createEvent($c, "front", "traffic light", "", 5),
        "1794647391.273952-tl0001");
    testing.assertEqual(
        eventPath("front", "traffic light"),
        "/events/front/traffic%20light/create");
    testing.assertEqual(eventPath("front", "fire hydrant"), "/events/front/fire%20hydrant/create");
    testing.assertEqual(eventPath("front", "door_bell-2"), "/events/front/door_bell-2/create");
    testing.assertEqual(eventPath("front", "a b c"), "/events/front/a%20b%20c/create");
    try {
        createEvent($c, "front door", "x", "", 1);
        missed("a camera with a space");
    } catch (e) {
        testing.assertContains($e.message, "a camera is 1 to 64 letters");
    }
    for (def bad in [
        "a/b",
        "",
        " person",
        "person ",
        "traffic  light",
        "a\tb",
        "caf\u00e9",
        "a%20b",
        "a+b",
        strings.replicate("x", 65)
    ]) {
        try {
            createEvent($c, "front", $bad, "", 1);
            missed($bad);
        } catch (e) {
            testing.assertEqual($e.kind, "frigate");
            testing.assertContains(
                $e.message,
                "a label is 1 to 64 letters, digits, _ and -, words split by single spaces");
        }
    }
    for (def bad in [-1, 86401]) {
        try {
            createEvent($c, "front", "x", "", $bad);
            missed(convert.toString($bad));
        } catch (e) {
            testing.assertContains($e.message, "the duration in seconds must be 0 to 86400");
        }
    }
    try {
        setSubLabel($c, EVENT, strings.replicate("x", 101), 0.0);
        missed("a long sub label");
    } catch (e) {
        testing.assertContains($e.message, "a sub label is at most 100 characters");
    }
    try {
        setSubLabel($c, EVENT, "x", 1.5);
        missed("a score over 1");
    } catch (e) {
        testing.assertContains($e.message, "a sub label score is");
    }
    def seen as list of string init stopFake($f);
    def j as string init "|Content-Type=application/json";
    def auth as string init "|Authorization=Bearer " + TOKEN;
    testing.assertEqual($seen[0], "DELETE /api/events/" + EVENT + $auth + "|");
    testing.assertEqual($seen[1], "POST /api/events/" + EVENT + "/retain" + $auth + "|");
    testing.assertEqual($seen[2], "DELETE /api/events/" + EVENT + "/retain" + $auth + "|");
    testing.assertEqual(
        $seen[3],
        "POST /api/events/" + EVENT + "/sub_label" + $j + $auth +
            '|{"subLabel":"alice","subLabelScore":0.8}');
    testing.assertEqual(
        $seen[4],
        "POST /api/events/" + EVENT + "/sub_label" + $j + $auth + '|{"subLabel":""}');
    testing.assertEqual($seen[5], "PUT /api/events/" + EVENT + "/end" + $j + $auth + '|{}');
    testing.assertEqual(
        $seen[6],
        "POST /api/events/front/doorbell/create" + $j + $auth + '|{"duration":30}');
    testing.assertEqual(
        $seen[7],
        "POST /api/events/front/doorbell/create" + $j + $auth +
            '|{"duration":null,"sub_label":"ring \"1\""}');
    testing.assertEqual(
        $seen[9],
        "POST /api/events/front/traffic light/create" + $j + $auth + '|{"duration":5}');
}

func testEventMedia() {
    def f as Fake init startFake({
        "GET /api/events/" + EVENT + "/snapshot.jpg": "200\nContent-Type: image/jpeg\n\nSNAP",
        "GET /api/events/" + EVENT + "/thumbnail.webp": "200\nContent-Type: image/webp\n\nTHUMB",
        "GET /api/events/" + EVENT + "/clip.mp4?padding=5": "200\nContent-Type: video/mp4\n\nCLIP",
        "GET /api/events/" + EVENT +
            "/clip.mp4?padding=0": answer(
            404,
            '{"success":false,"message":"Live frame not available"}')
    });
    def c as Client init fakeClient($f);
    testing.assertEqual(encoding.decode("utf-8", eventSnapshot($c, EVENT)), "SNAP");
    testing.assertEqual(encoding.decode("utf-8", eventThumbnail($c, EVENT, "webp")), "THUMB");
    testing.assertEqual(encoding.decode("utf-8", eventClip($c, EVENT, 5)), "CLIP");
    try {
        eventClip($c, EVENT, 0);
        missed("a 404");
    } catch (e) {
        testing.assertEqual($e.kind, "frigate.http");
        testing.assertEqual($e.status, 404);
    }
    try {
        eventThumbnail($c, EVENT, "gif");
        missed("a gif");
    } catch (e) {
        testing.assertContains($e.message, "an image format is jpg, png or webp");
    }
    try {
        eventClip($c, EVENT, 3601);
        missed("too much padding");
    } catch (e) {
        testing.assertContains($e.message, "the padding in seconds must be 0 to 3600");
    }
    stopFake($f);
}

func testReviews() {
    def f as Fake init startFake({
        "GET /api/review?severity=alert&reviewed=0": answer(200, "[" + REVIEW_JSON + "]"),
        "GET /api/review/" + REVIEW: answer(200, REVIEW_JSON),
        "POST /api/reviews/viewed": answer(200, DONE)
    });
    def c as Client init fakeClient($f);
    def got as list of Review init reviews($c, ["severity=alert", "reviewed=0"]);
    testing.assertEqual(len($got), 1);
    def r as Review init $got[0];
    testing.assertEqual($r.id, REVIEW);
    testing.assertEqual($r.camera, "front");
    testing.assertEqual($r.severity, "alert");
    testing.assertEqual($r.startTime, 1794646971.714268);
    testing.assertEqual($r.endTime, 0.0);
    testing.assertTrue($r.inProgress);
    testing.assertTrue($r.reviewed);
    testing.assertEqual($r.events, [EVENT]);
    testing.assertEqual($r.objects, ["person: tester"]);
    testing.assertEqual($r.zones, ["porch"]);
    testing.assertEqual(review($c, REVIEW).severity, "alert");
    markReviewed($c, [REVIEW], true);
    markReviewed($c, [REVIEW, "1794646972-abcdef"], false);
    try {
        markReviewed($c, [], true);
        missed("no ids");
    } catch (e) {
        testing.assertContains($e.message, "the number of review items must be 1 to 1000");
    }
    try {
        markReviewed($c, ["x"], true);
        missed("a bad id");
    } catch (e) {
        testing.assertContains($e.message, "a review item id is");
    }
    def seen as list of string init stopFake($f);
    testing.assertContains($seen[2], '|{"ids":["' + REVIEW + '"],"reviewed":true}');
    testing.assertContains(
        $seen[3],
        '|{"ids":["' + REVIEW + '","1794646972-abcdef"],"reviewed":false}');
}
