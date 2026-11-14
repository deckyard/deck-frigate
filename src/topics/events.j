# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# frigate - events: tracked objects (Frigate's events) with their snapshots,
# thumbnails and clips, manual events, sub labels and retention; review
# items (alerts and detections) and their reviewed marks. Spliced into
# frigate.j via include.

/** The longest sub label Frigate stores: 100 characters. */
export def const MAX_SUB_LABEL as int init 100;

/**
 * One tracked object, what Frigate calls an event: a person, car, dog, ...
 * seen by one camera from a start to an end time.
 *
 * @field id {string} the event's id, such as `1794646971.714268-8qyqhn`
 * @field camera {string} the camera that saw it
 * @field label {string} what it is: `person`, `car`, ...
 * @field subLabel {string} a recognised face, plate owner or a label set by `setSubLabel`; `""` when none
 * @field score {float} the best detection score, 0 to 1; 0 when the server sends none
 * @field startTime {float} when it was first seen, Unix seconds
 * @field endTime {float} when it was last seen, Unix seconds; 0 while it is still tracked
 * @field inProgress {bool} it is still tracked
 * @field zones {list of string} the zones it entered
 * @field hasClip {bool} a clip can be read with `eventClip`
 * @field hasSnapshot {bool} a snapshot can be read with `eventSnapshot`
 * @field retained {bool} it is kept regardless of the retention settings
 * @field raw {json.Value} the event as the server sent it
 */
export def struct Event {
    id as string,
    camera as string,
    label as string,
    subLabel as string,
    score as float,
    startTime as float,
    endTime as float,
    inProgress as bool,
    zones as list of string,
    hasClip as bool,
    hasSnapshot as bool,
    retained as bool,
    raw as json.Value
};

/**
 * One review item: a stretch of activity on one camera that the UI lists
 * for review, an alert or a detection, with the events in it.
 *
 * @field id {string} the item's id
 * @field camera {string} the camera
 * @field severity {string} `alert` or `detection`
 * @field startTime {float} when it began, Unix seconds
 * @field endTime {float} when it ended, Unix seconds; 0 while it is going on
 * @field inProgress {bool} it is going on
 * @field reviewed {bool} the signed-in user marked it reviewed; false where the server does not say (`review` of one item)
 * @field events {list of string} the ids of the events in it
 * @field objects {list of string} what was seen, such as `person` or `person: alice`
 * @field zones {list of string} the zones entered
 * @field raw {json.Value} the item as the server sent it
 */
export def struct Review {
    id as string,
    camera as string,
    severity as string,
    startTime as float,
    endTime as float,
    inProgress as bool,
    reviewed as bool,
    events as list of string,
    objects as list of string,
    zones as list of string,
    raw as json.Value
};

/**
 * The sub label of an event: a string, or `[label, score]` from older
 * servers.
 *
 * @param v {json.Value} the event
 * @return {string} the sub label, `""` when none
 */
func subLabelOf(v as json.Value) {
    if (json.typeOf($v, "/sub_label") == "list") {
        return textAt($v, "/sub_label/0");
    }
    return textAt($v, "/sub_label");
}

/**
 * An event from the server's JSON.
 *
 * @param v {json.Value} the event
 * @return {Event} the event
 */
func eventFrom(v as json.Value) {
    if (json.typeOf($v) != "map" or not regex.matches(ITEM_ID, textAt($v, "/id"))) {
        fail("the server returned an event without a valid id");
    }
    def score as float init numAt($v, "/data/top_score");
    if ($score == 0.0) {
        $score = numAt($v, "/top_score");
    }
    if ($score == 0.0) {
        $score = numAt($v, "/data/score");
    }
    def ends as string init json.typeOf($v, "/end_time");
    return Event{
        id: textAt($v, "/id"),
        camera: textAt($v, "/camera"),
        label: textAt($v, "/label"),
        subLabel: subLabelOf($v),
        score: $score,
        startTime: numAt($v, "/start_time"),
        endTime: numAt($v, "/end_time"),
        inProgress: $ends == "null" or $ends == "missing",
        zones: textsAt($v, "/zones"),
        hasClip: boolAt($v, "/has_clip"),
        hasSnapshot: boolAt($v, "/has_snapshot"),
        retained: boolAt($v, "/retain_indefinitely"),
        raw: $v
    };
}

/**
 * Events, newest first, filtered by the server. Thumbnails are left out
 * unless the query asks for them (`include_thumbnails=1`): each is a
 * base64 JPEG in `raw`.
 *
 * @param c {Client} the client
 * @param query {list of string} parameters as `name=value`: `cameras=front,back`, `labels=person,car`, `zones=...`, `sub_labels=...`, `after=<unix>`, `before=<unix>`, `has_clip=1`, `has_snapshot=1`, `in_progress=0`, `min_score=0.7`, `favorites=1` (retained), `limit=100` (the server's default), `offset=...`, `sort=date_desc`, ...
 * @return {list of Event} the events
 * @throws {HttpError} kind "frigate.http" when the server refuses a parameter (422, with `fields`) or the status is not 2xx
 * @throws {Error} kind "frigate" when a parameter is malformed or the request fails
 * @example
 *   for (def e in frigate.events($c, ["cameras=front", "labels=person", "limit=20"])) {
 *       io.printf("%s %s %f|prec=2\n", $e.id, $e.label, $e.score);
 *   }
 */
export func events(c as Client, query as list of string) {
    def q as list of string init $query;
    if (not hasParam($q, "include_thumbnails")) {
        $q[] = "include_thumbnails=0";
    }
    def v as json.Value init request($c, "GET", "/events" + queryOf($q), "", "events");
    def out as list of Event init [];
    for (def i in 0..listLength($v, "events")) {
        $out[] = eventFrom(json.get($v, "/" + convert.toString($i)));
    }
    return $out;
}

/**
 * One event.
 *
 * @param c {Client} the client
 * @param id {string} the event's id
 * @return {Event} the event
 * @throws {HttpError} kind "frigate.http" when there is no such event (404) or the status is not 2xx
 * @throws {Error} kind "frigate" when the id is malformed or the request fails
 */
export func event(c as Client, id as string) {
    checkItemId($id, "an event id");
    return eventFrom(request($c, "GET", "/events/" + $id, "", "event " + $id));
}

/**
 * Delete an event with its snapshot and clip. Needs the admin role. The
 * server deletes it through its event queue: `event` finds it for a moment
 * longer.
 *
 * @param c {Client} the client
 * @param id {string} the event's id
 * @throws {HttpError} kind "frigate.http" when there is no such event (404), the user is no admin (403), or the status is not 2xx
 * @throws {Error} kind "frigate" when the id is malformed or the request fails
 */
export func deleteEvent(c as Client, id as string) {
    checkItemId($id, "an event id");
    command($c, "DELETE", "/events/" + $id, "", "delete event " + $id);
}

/**
 * Keep an event regardless of the retention settings, or stop keeping it.
 * Needs the admin role. Like every change to an event, the server applies
 * it through its event queue: `event` shows it after a moment.
 *
 * @param c {Client} the client
 * @param id {string} the event's id
 * @param keep {bool} true to keep it, false to let retention remove it again
 * @throws {HttpError} kind "frigate.http" when there is no such event (404), the user is no admin (403), or the status is not 2xx
 * @throws {Error} kind "frigate" when the id is malformed or the request fails
 */
export func retainEvent(c as Client, id as string, keep as bool) {
    checkItemId($id, "an event id");
    def method as string init "DELETE";
    if ($keep) {
        $method = "POST";
    }
    command($c, $method, "/events/" + $id + "/retain", "", "retain event " + $id);
}

/**
 * Set an event's sub label, such as a name for a person. Needs the admin
 * role. The server applies it through its event queue: `event` shows it
 * after a moment.
 *
 * @param c {Client} the client
 * @param id {string} the event's id
 * @param subLabel {string} the sub label, 1 to `MAX_SUB_LABEL` characters; `""` clears it
 * @param score {float} how sure, above 0 to 1; 0 to send none
 * @throws {HttpError} kind "frigate.http" when there is no such event (404), the user is no admin (403), or the status is not 2xx
 * @throws {Error} kind "frigate" when the id, sub label or score is out of range, or the request fails
 */
export func setSubLabel(c as Client, id as string, subLabel as string, score as float) {
    checkItemId($id, "an event id");
    if (len($subLabel) > MAX_SUB_LABEL) {
        fail(io.sprintf(
            "a sub label is at most %d characters, got %d",
            MAX_SUB_LABEL,
            len($subLabel)));
    }
    if ($score < 0.0 or $score > 1.0) {
        fail("a sub label score is above 0 to 1, or 0 for none");
    }
    def body as json.Value init json.map({"subLabel": $subLabel});
    if ($score > 0.0) {
        $body = json.set($body, "/subLabelScore", $score);
    }
    command(
        $c,
        "POST",
        "/events/" + $id + "/sub_label",
        json.encode($body),
        "sub label of event " + $id);
}

/**
 * Create an event by hand, such as for a doorbell press, with a snapshot
 * of the current frame and the recording around it. Needs the admin role.
 * The server stores it through its event queue: `event` finds it after a
 * moment, and answers 404 before that.
 *
 * @param c {Client} the client
 * @param camera {string} the camera
 * @param label {string} its label, such as `doorbell` or `traffic light`: 1 to 64 letters, digits, `_` and `-`, words split by single spaces (sent percent-encoded)
 * @param subLabel {string} a sub label, `""` for none
 * @param seconds {int} how long it lasts, 1 to 86400; 0 to keep it open until `endEvent`
 * @return {string} the new event's id
 * @throws {HttpError} kind "frigate.http" when there is no such camera (404), the user is no admin (403), or the status is not 2xx
 * @throws {Error} kind "frigate" when the camera, label or duration is malformed, or the request fails
 * @example
 *   def id as string init frigate.createEvent($c, "front", "doorbell", "", 30);
 */
export func createEvent(
    c as Client,
    camera as string,
    label as string,
    subLabel as string,
    seconds as int) {
    checkName($camera, "a camera");
    checkLabel($label);
    checkRange($seconds, 0, 86400, "the duration in seconds");
    if (len($subLabel) > MAX_SUB_LABEL) {
        fail(io.sprintf(
            "a sub label is at most %d characters, got %d",
            MAX_SUB_LABEL,
            len($subLabel)));
    }
    def body as json.Value init json.decode('{"duration": null}');
    if ($seconds > 0) {
        $body = json.set($body, "/duration", $seconds);
    }
    if ($subLabel != "") {
        $body = json.set($body, "/sub_label", $subLabel);
    }
    def what as string init "create event on " + shown($camera);
    def v as json.Value init command(
        $c,
        "POST",
        eventPath($camera, $label),
        json.encode($body),
        $what);
    def id as string init textAt($v, "/event_id");
    if (not regex.matches(ITEM_ID, $id)) {
        fail($what + ": the server returned no event id");
    }
    return $id;
}

/**
 * The API path that creates an event, the label percent-encoded (a space
 * as `%20`).
 *
 * @param camera {string} the camera, checked
 * @param label {string} the label, checked
 * @return {string} such as `/events/front/traffic%20light/create`
 */
func eventPath(camera as string, label as string) {
    return "/events/" + $camera + "/" + uri.encode($label) + "/create";
}

/**
 * End an event created with `createEvent` and no duration. Needs the admin
 * role. The server applies it through its event queue: `event` shows the
 * end time after a moment.
 *
 * @param c {Client} the client
 * @param id {string} the event's id
 * @throws {HttpError} kind "frigate.http" when there is no such event (404), the user is no admin (403), or the status is not 2xx
 * @throws {Error} kind "frigate" when the id is malformed or the request fails
 */
export func endEvent(c as Client, id as string) {
    checkItemId($id, "an event id");
    command($c, "PUT", "/events/" + $id + "/end", '{}', "end event " + $id);
}

/**
 * An event's snapshot, a JPEG with the bounding box drawn.
 *
 * @param c {Client} the client
 * @param id {string} the event's id
 * @return {bytes} the JPEG
 * @throws {HttpError} kind "frigate.http" when there is no such event or snapshot (404) or the status is not 2xx
 * @throws {Error} kind "limit" when it is over the media cap; kind "frigate" when the id is malformed or the request fails
 */
export func eventSnapshot(c as Client, id as string) {
    checkItemId($id, "an event id");
    return media($c, "/api/events/" + $id + "/snapshot.jpg", "snapshot of event " + $id);
}

/**
 * An event's thumbnail, a small cropped image.
 *
 * @param c {Client} the client
 * @param id {string} the event's id
 * @param format {string} `jpg`, `png` or `webp`
 * @return {bytes} the image
 * @throws {HttpError} kind "frigate.http" when there is no such event (404) or the status is not 2xx
 * @throws {Error} kind "limit" when it is over the media cap; kind "frigate" when the id or format is malformed or the request fails
 */
export func eventThumbnail(c as Client, id as string, format as string) {
    checkItemId($id, "an event id");
    checkFormat($format);
    return media($c, "/api/events/" + $id + "/thumbnail." + $format, "thumbnail of event " + $id);
}

/**
 * Refuse an image format Frigate does not render.
 *
 * @param format {string} the format
 */
func checkFormat(format as string) {
    if (not lists.contains(["jpg", "png", "webp"], $format)) {
        fail("an image format is jpg, png or webp, got " + shown($format));
    }
}

/**
 * An event's clip, an MP4 cut from the recordings.
 *
 * @param c {Client} the client
 * @param id {string} the event's id
 * @param padding {int} seconds of recording added before and after, 0 to 3600
 * @return {bytes} the MP4
 * @throws {HttpError} kind "frigate.http" when there is no such event or no recording of it (404, 400) or the status is not 2xx
 * @throws {Error} kind "limit" when it is over the media cap; kind "frigate" when the id is malformed or the request fails
 */
export func eventClip(c as Client, id as string, padding as int) {
    checkItemId($id, "an event id");
    checkRange($padding, 0, 3600, "the padding in seconds");
    return media(
        $c,
        "/api/events/" + $id + "/clip.mp4" + queryOf(["padding=" + convert.toString($padding)]),
        "clip of event " + $id);
}

/**
 * A review item from the server's JSON.
 *
 * @param v {json.Value} the item
 * @return {Review} the item
 */
func reviewFrom(v as json.Value) {
    if (json.typeOf($v) != "map" or not regex.matches(ITEM_ID, textAt($v, "/id"))) {
        fail("the server returned a review item without a valid id");
    }
    def ends as string init json.typeOf($v, "/end_time");
    return Review{
        id: textAt($v, "/id"),
        camera: textAt($v, "/camera"),
        severity: textAt($v, "/severity"),
        startTime: numAt($v, "/start_time"),
        endTime: numAt($v, "/end_time"),
        inProgress: $ends == "null" or $ends == "missing",
        reviewed: boolAt($v, "/has_been_reviewed"),
        events: textsAt($v, "/data/detections"),
        objects: textsAt($v, "/data/objects"),
        zones: textsAt($v, "/data/zones"),
        raw: $v
    };
}

/**
 * Review items, newest first, filtered by the server.
 *
 * @param c {Client} the client
 * @param query {list of string} parameters as `name=value`: `cameras=front`, `labels=person`, `zones=...`, `severity=alert` or `detection`, `reviewed=0` or `1`, `after=<unix>`, `before=<unix>`, `limit=...`
 * @return {list of Review} the items
 * @throws {HttpError} kind "frigate.http" when the server refuses a parameter (422, with `fields`) or the status is not 2xx
 * @throws {Error} kind "frigate" when a parameter is malformed or the request fails
 * @example
 *   for (def r in frigate.reviews($c, ["severity=alert", "reviewed=0"])) {
 *       io.printf("%s %s %a\n", $r.camera, $r.id, $r.objects);
 *   }
 */
export func reviews(c as Client, query as list of string) {
    def v as json.Value init request($c, "GET", "/review" + queryOf($query), "", "review items");
    def out as list of Review init [];
    for (def i in 0..listLength($v, "review items")) {
        $out[] = reviewFrom(json.get($v, "/" + convert.toString($i)));
    }
    return $out;
}

/**
 * One review item.
 *
 * @param c {Client} the client
 * @param id {string} the item's id
 * @return {Review} the item; its `reviewed` is false, the server does not say here
 * @throws {HttpError} kind "frigate.http" when there is no such item (404) or the status is not 2xx
 * @throws {Error} kind "frigate" when the id is malformed or the request fails
 */
export func review(c as Client, id as string) {
    checkItemId($id, "a review item id");
    return reviewFrom(request($c, "GET", "/review/" + $id, "", "review item " + $id));
}

/**
 * Mark review items reviewed, or not reviewed, for the signed-in user.
 *
 * @param c {Client} the client
 * @param ids {list of string} the items' ids, 1 to 1000
 * @param reviewed {bool} true for reviewed
 * @throws {HttpError} kind "frigate.http" when the status is not 2xx
 * @throws {Error} kind "frigate" when an id is malformed, the list is empty or too long, or the request fails
 */
export func markReviewed(c as Client, ids as list of string, reviewed as bool) {
    checkRange(len($ids), 1, 1000, "the number of review items");
    for (def id in $ids) {
        checkItemId($id, "a review item id");
    }
    def body as json.Value init json.set(
        json.map({"ids": json.list($ids)}),
        "/reviewed",
        $reviewed);
    command($c, "POST", "/reviews/viewed", json.encode($body), "mark review items");
}
