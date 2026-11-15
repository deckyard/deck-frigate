<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/frigate

[Frigate](https://frigate.video/) is a self-hosted network video recorder
that detects objects in camera streams. This deck is a client for its HTTP
API: the tracked objects it calls events, with their snapshots and clips;
the review items the UI lists as alerts and detections; recordings, clips
and frames cut from them, and exports; and the cameras themselves, their
configuration, live numbers and switches.

- [Signing in](signing-in.md): the two ports, passwords, tokens,
  certificates.
- [Events and review](events.md): events, filters, media, manual events,
  sub labels, review items.
- [Recordings and exports](recordings.md): segments, hours, clips, frames,
  storage, exports.
- [Cameras](cameras.md): configuration, stats, the latest frame, switches,
  restart.
- [Cheatsheet](cheatsheet.md): every export.

Frigate also publishes what happens live over MQTT (`frigate/events`,
`frigate/reviews`, per-camera state topics). That feed is the bundled
`mqtt` module's job, not this deck's: use it to react the moment an object
appears, and this deck to fetch the snapshot or clip afterwards.

## Conventions

Snippets assume this import:

```jennifer
import "@deckyard/frigate/" as frigate;
```

A request the server refused throws `frigate.HttpError`, kind
`frigate.http`, with the HTTP `status` and, for a 422, the validation
errors as `fields`; a response over a cap (or nested past the JSON decoder's
caps) is kind `"limit"`, a deadline
that passed kind `"timeout"`, a connection the server closed mid-answer
kind `"closed"`, a server that cannot be reached, resets the connection or
fails the TLS handshake kind `"net"` (the `net.NetError` that `http` threw,
with `op`, `reason`, `sent` and `replied` to read); any other failure is
`Error{kind: "frigate"}` (a cancelled task stays kind `"cancelled"`):

```jennifer
try {
    def e as frigate.Event init frigate.event($c, $id);
} catch (err) {
    if ($err.kind == "frigate.http" and $err.status == 404) {
        io.printf("no such event\n");
    } else {
        throw $err;
    }
}
```

Frigate also refuses some requests with a 2xx status and
`{"success": false, "message": ...}`; the deck throws those as kind
`"frigate"` with the server's message.

Times are `float` Unix seconds, as Frigate keeps them:
`convert.toFloat(time.unix(time.now()))` is now. Every request has a
deadline (30 s), JSON responses a cap (16 MiB) and images and video another
(256 MiB). Camera names, labels, ids and query parameter names are checked
before they go into a URL. Every GET carries `X-Cache-Bypass: 1`: nginx in
front of port 8971 otherwise answers a read repeated within 5 seconds from
its cache, so a read right after a change would show the old state.

The deck follows Frigate 0.18 (checked against 0.18.2 and its OpenAPI
description). Calls marked admin in the [cheatsheet](cheatsheet.md) need a
user with the admin role.
