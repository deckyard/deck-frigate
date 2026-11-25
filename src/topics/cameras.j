# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# frigate - cameras: the configuration and camera names, live stats, the
# latest frame, labels, switching camera features, and restarting the
# server. Spliced into frigate.j via include.

# the camera features `switchCamera` turns on and off
def const SWITCHES as list of string init [
    "enabled",
    "detect",
    "motion",
    "recordings",
    "snapshots",
    "audio",
    "audio_transcription",
    "notifications",
    "review_alerts",
    "review_detections",
    "object_descriptions",
    "review_descriptions",
    "improve_contrast",
    "ptz_autotracker",
    "birdseye"
];

# the named parts `switchPart` turns on and off
def const PARTS as list of string init ["zone", "motion_mask", "object_mask"];

/**
 * One camera's live numbers.
 *
 * @field name {string} the camera
 * @field cameraFps {float} frames per second coming from the camera
 * @field processFps {float} frames per second processed
 * @field detectionFps {float} object detections per second
 * @field detectionEnabled {bool} object detection is on
 * @field connection {string} the stream's state, such as `excellent`; `""` when the server does not say
 * @field reconnects {int} reconnects in the last hour
 */
export def struct CameraStats {
    name as string,
    cameraFps as float,
    processFps as float,
    detectionFps as float,
    detectionEnabled as bool,
    connection as string,
    reconnects as int
};

/**
 * The configuration the server runs with, every default filled in.
 *
 * @param c {Client} the client
 * @return {json.Value} the configuration, such as `/cameras/front/record/enabled`
 * @throws {HttpError} kind "frigate.http" when the status is not 2xx
 * @throws {Error} kind "frigate" when the request fails
 * @example
 *   def cfg as json.Value init frigate.config($c);
 *   io.printf("%t\n", json.asBool($cfg, "/cameras/front/record/enabled"));
 */
export func config(c as Client) {
    def v as json.Value init request($c, "GET", "/config", "", "config");
    if (json.typeOf($v, "/cameras") != "map") {
        fail("config: the server returned no cameras");
    }
    return $v;
}

/**
 * The names of the configured cameras, sorted.
 *
 * @param c {Client} the client
 * @return {list of string} the names
 * @throws {HttpError} kind "frigate.http" when the status is not 2xx
 * @throws {Error} kind "frigate" when the request fails
 */
export func cameras(c as Client) {
    return lists.sort(json.keys(config($c), "/cameras"));
}

/**
 * The server's live numbers: cameras, detectors, processes, storage,
 * GPUs, uptime and version.
 *
 * @param c {Client} the client
 * @return {json.Value} the numbers, such as `/detectors/<name>/inference_speed` or `/service/uptime`
 * @throws {HttpError} kind "frigate.http" when the status is not 2xx
 * @throws {Error} kind "frigate" when the request fails
 */
export func stats(c as Client) {
    def v as json.Value init request($c, "GET", "/stats", "", "stats");
    if (json.typeOf($v) != "map") {
        fail("stats: the server returned no map");
    }
    return $v;
}

/**
 * Each camera's live numbers, by name.
 *
 * @param c {Client} the client
 * @return {list of CameraStats} one entry per camera
 * @throws {HttpError} kind "frigate.http" when the status is not 2xx
 * @throws {Error} kind "frigate" when the request fails
 * @example
 *   for (def s in frigate.cameraStats($c)) {
 *       io.printf("%s|pad=12 %f|prec=1 fps %s\n", $s.name, $s.cameraFps, $s.connection);
 *   }
 */
export func cameraStats(c as Client) {
    def v as json.Value init stats($c);
    def out as list of CameraStats init [];
    if (json.typeOf($v, "/cameras") != "map") {
        return $out;
    }
    for (def name in lists.sort(json.keys($v, "/cameras"))) {
        if (not regex.matches(NAME, $name)) {
            fail("stats: a camera name is malformed: " + shown($name));
        }
        def at as string init "/cameras/" + $name;
        $out[] = CameraStats{
            name: $name,
            cameraFps: numAt($v, $at + "/camera_fps"),
            processFps: numAt($v, $at + "/process_fps"),
            detectionFps: numAt($v, $at + "/detection_fps"),
            detectionEnabled: boolAt($v, $at + "/detection_enabled"),
            connection: textAt($v, $at + "/connection_quality"),
            reconnects: intAt($v, $at + "/reconnects_last_hour")
        };
    }
    return $out;
}

/**
 * The latest frame of a camera; while the camera is offline, the latest
 * preview frame.
 *
 * @param c {Client} the client
 * @param camera {string} the camera
 * @param format {string} `jpg`, `png` or `webp`
 * @param height {int} the height in pixels, 0 for the detect size
 * @return {bytes} the image
 * @throws {HttpError} kind "frigate.http" when there is no such camera (404) or the status is not 2xx
 * @throws {Error} kind "limit" when it is over the media cap; kind "frigate" when an argument is malformed or the request fails
 * @example
 *   fs.writeBytes("front.jpg", frigate.latestFrame($c, "front", "jpg", 0));
 */
export func latestFrame(c as Client, camera as string, format as string, height as int) {
    checkName($camera, "a camera");
    checkFormat($format);
    checkRange($height, 0, 4320, "the height");
    def query as list of string init [];
    if ($height > 0) {
        $query[] = "height=" + convert.toString($height);
    }
    return media(
        $c,
        "/api/" + $camera + "/latest." + $format + queryOf($query),
        "latest frame of " + shown($camera));
}

/**
 * The labels events were recorded with, sorted.
 *
 * @param c {Client} the client
 * @param camera {string} one camera, `""` for all
 * @return {list of string} the labels, such as `car`, `person`
 * @throws {HttpError} kind "frigate.http" when the status is not 2xx
 * @throws {Error} kind "frigate" when the camera is malformed or the request fails
 */
export func labels(c as Client, camera as string) {
    def query as list of string init [];
    if ($camera != "") {
        checkName($camera, "a camera");
        $query[] = "camera=" + $camera;
    }
    def v as json.Value init request($c, "GET", "/labels" + queryOf($query), "", "labels");
    listLength($v, "labels");
    return lists.sort(textsAt($v, ""));
}

/**
 * Refuse a camera for `switchCamera`: a name, or `*` for all.
 *
 * @param camera {string} the camera
 */
func checkTarget(camera as string) {
    if ($camera != "*") {
        checkName($camera, "a camera");
    }
}

/**
 * Turn a feature of a camera, or of every camera, on or off until the
 * server restarts. Needs the admin role.
 *
 * @param c {Client} the client
 * @param camera {string} the camera, `*` for all
 * @param feature {string} `enabled`, `detect`, `motion`, `recordings`, `snapshots`, `audio`, `audio_transcription`, `notifications`, `review_alerts`, `review_detections`, `object_descriptions`, `review_descriptions`, `improve_contrast`, `ptz_autotracker` or `birdseye`
 * @param on {bool} true for on
 * @throws {HttpError} kind "frigate.http" when there is no such camera (404), the server refuses (400), the user is no admin (403), or the status is not 2xx
 * @throws {Error} kind "frigate" when the camera or feature is malformed, or the request fails
 * @example
 *   frigate.switchCamera($c, "front", "detect", false);
 */
export func switchCamera(c as Client, camera as string, feature as string, on as bool) {
    checkTarget($camera);
    if (not lists.contains(SWITCHES, $feature)) {
        fail("a camera feature is one of " + strings.join(SWITCHES, ", ") + ", got " +
            shown($feature));
    }
    command(
        $c,
        "PUT",
        "/camera/" + $camera + "/set/" + $feature,
        onOff($on),
        $feature + " of " + shown($camera));
}

/**
 * Turn a zone, motion mask or object mask of a camera on or off until the
 * server restarts. Needs the admin role. Frigate 0.18 does not check the name:
 * one that is not in the configuration is accepted and does nothing.
 *
 * @param c {Client} the client
 * @param camera {string} the camera
 * @param part {string} `zone`, `motion_mask` or `object_mask`
 * @param name {string} the zone's or mask's name in the configuration
 * @param on {bool} true for on
 * @throws {HttpError} kind "frigate.http" when there is no such camera (404), the server refuses (400), the user is no admin (403), or the status is not 2xx
 * @throws {Error} kind "frigate" when an argument is malformed or the request fails
 */
export func switchPart(c as Client, camera as string, part as string, name as string, on as bool) {
    checkName($camera, "a camera");
    if (not lists.contains(PARTS, $part)) {
        fail("a camera part is zone, motion_mask or object_mask, got " + shown($part));
    }
    checkName($name, "a zone or mask name");
    command(
        $c,
        "PUT",
        "/camera/" + $camera + "/set/" + $part + "/" + $name,
        onOff($on),
        $part + " " + shown($name) + " of " + shown($camera));
}

/**
 * The body that switches a feature.
 *
 * @param on {bool} on or off
 * @return {string} `{"value":"ON"}` or `{"value":"OFF"}`
 */
func onOff(on as bool) {
    if ($on) {
        return '{"value":"ON"}';
    }
    return '{"value":"OFF"}';
}

/**
 * Restart Frigate. Needs the admin role. The server answers before it goes
 * down; it is back after some seconds. In Docker the process exits, so it
 * comes back only when the container has a restart policy.
 *
 * @param c {Client} the client
 * @throws {HttpError} kind "frigate.http" when the user is no admin (403) or the status is not 2xx
 * @throws {Error} kind "frigate" when the request fails
 */
export func restart(c as Client) {
    command($c, "POST", "/restart", "", "restart");
}
