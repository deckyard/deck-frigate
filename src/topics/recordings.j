# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# frigate - recordings: recorded segments and their hourly summary, clips
# and frames cut from them, storage use, and exports (start, list, wait,
# download, delete). Spliced into frigate.j via include.

/** The longest stretch a recording clip or an export may cover: 24 hours. */
export def const MAX_SPAN_SECONDS as int init 86400;

/**
 * The longest stretch one `recordings` call may cover: 6 hours. Each
 * segment carries a motion heatmap, so a day of steady motion is some 24 MB
 * of JSON; a day takes four calls.
 */
export def const MAX_RECORDINGS_SPAN_SECONDS as int init 21600;

# an export id: `<camera>_<suffix>`
def const EXPORT_ID as string init '^[A-Za-z0-9_-]{1,128}$';

# where Frigate keeps export files, and the file name of one
def const EXPORT_DIR as string init "/media/frigate/exports/";
def const EXPORT_FILE as string init '^[A-Za-z0-9_.-]{1,200}\.mp4$';

# how often `waitExport` asks, in milliseconds
def const EXPORT_POLL_MS as int init 1000;

/**
 * One recorded segment of a camera, usually 10 seconds.
 *
 * @field id {string} the segment's id
 * @field startTime {float} its start, Unix seconds
 * @field endTime {float} its end, Unix seconds
 * @field duration {float} its length in seconds
 * @field motion {int} how much motion it holds (changed pixels, summed)
 * @field objects {int} how many object detections it holds
 * @field sizeMb {float} its size on disk in MB
 */
export def struct Recording {
    id as string,
    startTime as float,
    endTime as float,
    duration as float,
    motion as int,
    objects as int,
    sizeMb as float
};

/**
 * One hour of a camera's recordings, in UTC.
 *
 * @field day {string} the date, `YYYY-MM-DD`
 * @field hour {int} the hour, 0 to 23
 * @field events {int} the events in it
 * @field motion {int} the motion in it
 * @field objects {int} the object detections in it
 * @field duration {float} the seconds recorded
 */
export def struct RecordingHour {
    day as string,
    hour as int,
    events as int,
    motion as int,
    objects as int,
    duration as float
};

/**
 * The disk space one camera's recordings take.
 *
 * @field camera {string} the camera
 * @field usageMb {float} the space taken, in MB
 * @field bandwidthMb {float} what it records per hour, in MB
 * @field usagePercent {float} its share of the recordings disk, 0 to 100
 */
export def struct Storage {
    camera as string,
    usageMb as float,
    bandwidthMb as float,
    usagePercent as float
};

/**
 * An export: a stretch of recording saved as one MP4 file that the
 * retention settings do not remove.
 *
 * @field id {string} the export's id
 * @field camera {string} the camera
 * @field name {string} its name
 * @field date {float} the start of the stretch, Unix seconds
 * @field videoPath {string} the file on the server, such as `/media/frigate/exports/front_20261114_090219-20261114_090249_f9pg1a.mp4`
 * @field inProgress {bool} it is still being written; `exportFile` waits for false
 */
export def struct Export {
    id as string,
    camera as string,
    name as string,
    date as float,
    videoPath as string,
    inProgress as bool
};

/**
 * Refuse a time range that is reversed or longer than `MAX_SPAN_SECONDS`.
 *
 * @param start {float} the start, Unix seconds
 * @param end {float} the end, Unix seconds
 */
func checkSpan(start as float, end as float) {
    checkTime($start, "the start");
    checkTime($end, "the end");
    if ($end <= $start) {
        fail("the end must be after the start");
    }
    if ($end - $start > convert.toFloat(MAX_SPAN_SECONDS)) {
        fail(io.sprintf("a time range is at most %d seconds", MAX_SPAN_SECONDS));
    }
}

/**
 * A camera's recorded segments in a time range, oldest first.
 *
 * @param c {Client} the client
 * @param camera {string} the camera
 * @param after {float} the start, Unix seconds
 * @param before {float} the end, Unix seconds; at most `MAX_RECORDINGS_SPAN_SECONDS` (6 hours) after the start, so a day takes four calls
 * @return {list of Recording} the segments
 * @throws {HttpError} kind "frigate.http" when the status is not 2xx
 * @throws {Error} kind "frigate" when the camera is malformed, the range reversed or over 6 hours, or the request fails
 * @example
 *   def now as float init convert.toFloat(time.unix(time.now()));
 *   def hour as list of frigate.Recording init frigate.recordings($c, "front", $now - 3600.0, $now);
 */
export func recordings(c as Client, camera as string, after as float, before as float) {
    checkName($camera, "a camera");
    checkSpan($after, $before);
    if ($before - $after > convert.toFloat(MAX_RECORDINGS_SPAN_SECONDS)) {
        fail(io.sprintf(
            "recordings cover at most %d seconds per call, got %s: ask in parts",
            MAX_RECORDINGS_SPAN_SECONDS,
            stamp($before - $after)));
    }
    def what as string init "recordings of " + shown($camera);
    def v as json.Value init request(
        $c,
        "GET",
        "/" + $camera + "/recordings" +
            queryOf(["after=" + stamp($after), "before=" + stamp($before)]),
        "",
        $what);
    def out as list of Recording init [];
    for (def i in 0..listLength($v, $what)) {
        def at as string init "/" + convert.toString($i);
        $out[] = Recording{
            id: textAt($v, $at + "/id"),
            startTime: numAt($v, $at + "/start_time"),
            endTime: numAt($v, $at + "/end_time"),
            duration: numAt($v, $at + "/duration"),
            motion: intAt($v, $at + "/motion"),
            objects: intAt($v, $at + "/objects"),
            sizeMb: numAt($v, $at + "/segment_size")
        };
    }
    return $out;
}

/**
 * The hours a camera has recordings for, newest day first, in UTC.
 *
 * @param c {Client} the client
 * @param camera {string} the camera
 * @return {list of RecordingHour} the hours
 * @throws {HttpError} kind "frigate.http" when the status is not 2xx
 * @throws {Error} kind "frigate" when the camera is malformed or the request fails
 */
export func recordingHours(c as Client, camera as string) {
    checkName($camera, "a camera");
    def what as string init "recording summary of " + shown($camera);
    def v as json.Value init request(
        $c,
        "GET",
        "/" + $camera + "/recordings/summary" + queryOf(["timezone=utc"]),
        "",
        $what);
    def out as list of RecordingHour init [];
    for (def i in 0..listLength($v, $what)) {
        def day as string init "/" + convert.toString($i);
        if (json.typeOf($v, $day + "/hours") != "list") {
            fail($what + ": a day without hours");
        }
        for (def j in 0..json.length($v, $day + "/hours")) {
            def at as string init $day + "/hours/" + convert.toString($j);
            def hour as string init textAt($v, $at + "/hour");
            if (not regex.matches('^([01][0-9]|2[0-3])$', $hour)) {
                fail($what + ": an hour is not 00 to 23: " + shown($hour));
            }
            $out[] = RecordingHour{
                day: textAt($v, $day + "/day"),
                hour: convert.toInt($hour, 10),
                events: intAt($v, $at + "/events"),
                motion: intAt($v, $at + "/motion"),
                objects: intAt($v, $at + "/objects"),
                duration: numAt($v, $at + "/duration")
            };
        }
    }
    return $out;
}

/**
 * The disk space each camera's recordings take. Needs the admin role.
 *
 * @param c {Client} the client
 * @return {list of Storage} one entry per camera, by name
 * @throws {HttpError} kind "frigate.http" when the user is no admin (403) or the status is not 2xx
 * @throws {Error} kind "frigate" when the request fails
 */
export func storage(c as Client) {
    def v as json.Value init request($c, "GET", "/recordings/storage", "", "storage");
    if (json.typeOf($v) != "map") {
        fail("storage: the server returned no map of cameras");
    }
    def out as list of Storage init [];
    for (def name in lists.sort(json.keys($v))) {
        def at as string init "/" + strings.replace(strings.replace($name, "~", "~0"), "/", "~1");
        if (json.typeOf($v, $at) != "map") {
            continue;
        }
        $out[] = Storage{
            camera: $name,
            usageMb: numAt($v, $at + "/usage"),
            bandwidthMb: numAt($v, $at + "/bandwidth"),
            usagePercent: numAt($v, $at + "/usage_percent")
        };
    }
    return $out;
}

/**
 * A clip cut from a camera's recordings, an MP4.
 *
 * @param c {Client} the client
 * @param camera {string} the camera
 * @param start {float} the start, Unix seconds
 * @param end {float} the end, Unix seconds; at most `MAX_SPAN_SECONDS` after the start
 * @return {bytes} the MP4
 * @throws {HttpError} kind "frigate.http" when nothing was recorded then (400) or the status is not 2xx
 * @throws {Error} kind "limit" when it is over the media cap; kind "frigate" when the camera or range is malformed, or the request fails
 * @example
 *   fs.writeBytes("front.mp4", frigate.recordingClip($c, "front", $t - 30.0, $t + 30.0));
 */
export func recordingClip(c as Client, camera as string, start as float, end as float) {
    checkName($camera, "a camera");
    checkSpan($start, $end);
    return media(
        $c,
        "/api/" + $camera + "/start/" + stamp($start) + "/end/" + stamp($end) + "/clip.mp4",
        "clip of " + shown($camera));
}

/**
 * One frame of a camera's recordings.
 *
 * @param c {Client} the client
 * @param camera {string} the camera
 * @param at {float} the moment, Unix seconds
 * @param format {string} `jpg` or `png` (Frigate renders no other here: it answers `webp` with a JPEG)
 * @param height {int} the height in pixels, 0 for the recorded size
 * @return {bytes} the image
 * @throws {HttpError} kind "frigate.http" when nothing was recorded then (404) or the status is not 2xx
 * @throws {Error} kind "limit" when it is over the media cap; kind "frigate" when an argument is malformed or the request fails
 */
export func recordingFrame(
    c as Client,
    camera as string,
    at as float,
    format as string,
    height as int) {
    checkName($camera, "a camera");
    checkTime($at, "the moment");
    if (not lists.contains(["jpg", "png"], $format)) {
        fail("a recorded frame's format is jpg or png, got " + shown($format));
    }
    checkRange($height, 0, 4320, "the height");
    def query as list of string init [];
    if ($height > 0) {
        $query[] = "height=" + convert.toString($height);
    }
    return media(
        $c,
        "/api/" + $camera + "/recordings/" + stamp($at) + "/snapshot." + $format + queryOf($query),
        "frame of " + shown($camera));
}

/**
 * An export from the server's JSON.
 *
 * @param v {json.Value} the export
 * @return {Export} the export
 */
func exportFrom(v as json.Value) {
    if (json.typeOf($v) != "map" or not regex.matches(EXPORT_ID, textAt($v, "/id"))) {
        fail("the server returned an export without a valid id");
    }
    return Export{
        id: textAt($v, "/id"),
        camera: textAt($v, "/camera"),
        name: textAt($v, "/name"),
        date: numAt($v, "/date"),
        videoPath: textAt($v, "/video_path"),
        inProgress: boolAt($v, "/in_progress")
    };
}

/**
 * Refuse an export id of the wrong form.
 *
 * @param id {string} the id
 */
func checkExportId(id as string) {
    if (not regex.matches(EXPORT_ID, $id)) {
        fail("an export id is letters, digits, _ and -, such as front_f9pg1a, got " + shown($id));
    }
}

/**
 * Start saving a stretch of a camera's recordings as an export. The server
 * queues it; `waitExport` waits for the file.
 *
 * @param c {Client} the client
 * @param camera {string} the camera
 * @param start {float} the start, Unix seconds
 * @param end {float} the end, Unix seconds; at most `MAX_SPAN_SECONDS` after the start
 * @param name {string} a name for it, at most 256 characters; `""` lets the server choose
 * @return {string} the export's id
 * @throws {HttpError} kind "frigate.http" when nothing was recorded then (400), there is no such camera (404), or the status is not 2xx
 * @throws {Error} kind "frigate" when an argument is malformed or the request fails
 * @example
 *   def id as string init frigate.startExport($c, "front", $t - 60.0, $t + 60.0, "parcel");
 *   def e as frigate.Export init frigate.waitExport($c, $id, 600000);
 */
export func startExport(
    c as Client,
    camera as string,
    start as float,
    end as float,
    name as string) {
    checkName($camera, "a camera");
    checkSpan($start, $end);
    if (len($name) > 256) {
        fail("an export name is at most 256 characters");
    }
    def body as json.Value init json.map();
    if ($name != "") {
        $body = json.set($body, "/name", $name);
    }
    def what as string init "export of " + shown($camera);
    def v as json.Value init command(
        $c,
        "POST",
        "/export/" + $camera + "/start/" + stamp($start) + "/end/" + stamp($end),
        json.encode($body),
        $what);
    def id as string init textAt($v, "/export_id");
    if (not regex.matches(EXPORT_ID, $id)) {
        fail($what + ": the server returned no export id");
    }
    return $id;
}

/**
 * The exports of the cameras the user may see, newest first, filtered by
 * the server.
 *
 * @param c {Client} the client
 * @param query {list of string} parameters as `name=value`, `[]` for all: `cameras=front,back`, `start_date=<unix>` and `end_date=<unix>` (by the export's start), `export_case_id=...`
 * @return {list of Export} the exports
 * @throws {HttpError} kind "frigate.http" when the server refuses a parameter (422, with `fields`) or the status is not 2xx
 * @throws {Error} kind "frigate" when a parameter is malformed or the request fails
 * @example
 *   def since as int init time.unix(time.now()) - 86400;
 *   for (def e in frigate.exports($c, ["cameras=front", "start_date=" + convert.toString($since)])) {
 *       io.printf("%s %s\n", $e.id, $e.name);
 *   }
 */
export func exports(c as Client, query as list of string) {
    def v as json.Value init request($c, "GET", "/exports" + queryOf($query), "", "exports");
    def out as list of Export init [];
    for (def i in 0..listLength($v, "exports")) {
        $out[] = exportFrom(json.get($v, "/" + convert.toString($i)));
    }
    return $out;
}

/**
 * One export.
 *
 * @param c {Client} the client
 * @param id {string} the export's id
 * @return {Export} the export
 * @throws {HttpError} kind "frigate.http" when there is no such export (404) or the status is not 2xx
 * @throws {Error} kind "frigate" when the id is malformed or the request fails
 */
export func exportInfo(c as Client, id as string) {
    checkExportId($id);
    return exportFrom(request($c, "GET", "/exports/" + $id, "", "export " + $id));
}

/**
 * Wait until an export's file is written, asking once a second.
 *
 * @param c {Client} the client
 * @param id {string} the export's id
 * @param ms {int} how long to wait, 1000 to 86400000 milliseconds
 * @return {Export} the finished export
 * @throws {HttpError} kind "frigate.http" when there is no such export (404; also when it failed, which removes it) or the status is not 2xx
 * @throws {Error} kind "timeout" when it is still being written after `ms`; kind "frigate" when the id is malformed or a request fails
 */
export func waitExport(c as Client, id as string, ms as int) {
    checkExportId($id);
    checkRange($ms, 1000, 86400000, "the wait");
    def started as int init time.unixMillis(time.now());
    while (true) {
        def e as Export init exportInfo($c, $id);
        if (not $e.inProgress) {
            return $e;
        }
        def left as int init $started + $ms - time.unixMillis(time.now());
        if ($left <= 0) {
            failTimeout(io.sprintf("export %s: still being written after %d ms", $id, $ms));
        }
        def pause as int init EXPORT_POLL_MS;
        if ($left < $pause) {
            $pause = $left;
        }
        time.sleep(time.fromMilliseconds($pause));
    }
}

/**
 * An export's file, an MP4. The server serves it outside the API, from
 * `/exports/`.
 *
 * @param c {Client} the client
 * @param e {Export} the export, finished
 * @return {bytes} the MP4
 * @throws {HttpError} kind "frigate.http" when the file is gone (404) or the status is not 2xx
 * @throws {Error} kind "limit" when it is over the media cap; kind "frigate" when the export is still being written, its path is not in the exports directory, or the request fails
 * @example
 *   fs.writeBytes("parcel.mp4", frigate.exportFile($c, frigate.waitExport($c, $id, 600000)));
 */
export func exportFile(c as Client, e as Export) {
    if ($e.inProgress) {
        fail("export " + shown($e.id) + " is still being written: waitExport first");
    }
    if (not strings.startsWith($e.videoPath, EXPORT_DIR) or
        not regex.matches(EXPORT_FILE, $e.videoPath[len(EXPORT_DIR)..])) {
        fail("export " + shown($e.id) + ": its file " + shown($e.videoPath) +
            " is not in " + EXPORT_DIR);
    }
    return media($c, "/exports/" + $e.videoPath[len(EXPORT_DIR)..], "file of export " + $e.id);
}

/**
 * Delete exports with their files. Needs the admin role. Either all are
 * deleted or none.
 *
 * @param c {Client} the client
 * @param ids {list of string} the exports' ids, 1 to 1000
 * @throws {HttpError} kind "frigate.http" when one does not exist (404), one is still being written (400), the user is no admin (403), or the status is not 2xx
 * @throws {Error} kind "frigate" when an id is malformed, the list is empty or too long, or the request fails
 */
export func deleteExports(c as Client, ids as list of string) {
    checkRange(len($ids), 1, 1000, "the number of exports");
    for (def id in $ids) {
        checkExportId($id);
    }
    command(
        $c,
        "POST",
        "/exports/delete",
        json.encode(json.map({"ids": json.list($ids)})),
        "delete exports");
}
