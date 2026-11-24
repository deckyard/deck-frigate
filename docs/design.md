<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

A client for the HTTP API of Frigate™, the network video recorder: sign-in;
events with filters, snapshots, thumbnails and clips, manual events, sub
labels and retention; review items and reviewed marks; recordings, the hourly
summary, recording clips and frames, storage; exports (start, wait, download,
delete); config, stats, the latest frame, labels, camera feature switches and
restart. `call` and `fetch` reach the rest of the API.

Out of scope:

- **The live feed.** Frigate publishes detections and state over MQTT; the
  bundled `mqtt` module consumes it.
- **Video.** Clips, frames and exports come back as bytes; decoding or
  re-encoding them is for other tools.
- **Value settings of cameras.** `switchCamera` covers only the on / off
  features; other settings go through `call`.

## Decisions

- **The live server is the source of truth.** The API follows Frigate's
  OpenAPI™ description (checked at v0.18.2), but the description is wrong in
  places: review start and end times are Unix numbers, not date-times;
  `/version` is not public on the authenticated port; a single review item
  has no reviewed flag; a recording's WebP snapshot is a JPEG. Where they
  differ, the deck follows what 0.18.2 answers.
- **The base URL is the server root**; the deck adds `/api`. Export files
  are served from `/exports/`, outside the API. A base ending in `/api` is
  refused.
- **Sign-in turns the cookie into a bearer token.** `POST /api/login` sets
  the JWT only as a cookie and returns an empty body. The deck takes the
  token from `set-cookie` and sends it as `Authorization: Bearer`. Because
  `auth.cookie_name` renames the cookie, it falls back to the one cookie
  whose value is a JWT. There is no logout: Frigate's logout only clears the
  cookie, and the token stays valid until the session length passes.
- **Caching is bypassed.** The authenticated port's nginx caches every 200
  JSON answer for 5 s, so a new export did not show in the list right after
  it was made. Every GET sends `X-Cache-Bypass: 1`. Event changes still lag
  for about a second, since Frigate applies them through its event queue;
  the docs say so.
- **Times are `float` Unix seconds**, written into URLs with at most six
  decimals and no trailing zeros. Clip and export ranges are capped at
  `MAX_SPAN_SECONDS` (a day). `recordings` is capped at
  `MAX_RECORDINGS_SPAN_SECONDS` (6 h): each segment carries a motion heat
  map, so a day of steady motion is about 24 MB, over the JSON cap; the docs
  page a day in four calls. `recordings` always sends both bounds, because
  Frigate fixes their defaults at server start.
- **Names are checked.** Camera, zone and mask names allow no spaces; labels
  for `createEvent` are words of letters, digits, `_` and `-` separated by
  single spaces (COCO's `traffic light`), at most 64 characters,
  percent-encoded in the path. Sub labels are at most `MAX_SUB_LABEL` (100).
- **`events` leaves out thumbnails** unless asked, since each is a base64
  JPEG inside the JSON.
- **`exports` takes a query list** like `events` (cameras, date range, case
  id) rather than fixed parameters; this changed the signature in 0.3.0.
- **Media reads refuse a JSON or HTML body** on a 2xx, so an error page is
  never handed back as an image or clip.

## Errors

- A status that is not 2xx throws `HttpError{kind, message, status,
  fields}` with kind `"frigate.http"`. `fields` holds the validation errors
  of a FastAPI 422 answer, keyed by location joined with dots
  (`query.limit`). The message reads the explanation from whatever shape the
  body has: a JSON string, `message`, `detail` as text or list, or nginx's
  HTML on a 401.
- A 2xx answer of `{"success": false}` and local validation are
  `Error{kind: "frigate"}`.
- Generic kinds: a reached cap (a body over its cap, or a reply nested past
  the JSON decoder's caps) is `"limit"`; a deadline in a request or in
  `waitExport` is `"timeout"`; a body cut short by the server is `"closed"`;
  a cancelled task passes on as `"cancelled"`; a server that cannot be
  reached (refused, reset, unreachable, DNS, TLS) is the `net.NetError`
  (kind `"net"`) that `http` threw, with its `op`, `reason`, `sent` and
  `replied`. The deck retries nothing.

## Security and limits

- **Two ports, two stances.** Port 8971 needs sign-in. Port 5000 is
  unauthenticated with admin rights and plain http, so a plain http URL is
  refused off loopback unless `withPlainHttp`. The check runs on every
  request, so `withPlainHttp(client(...))` works.
- **Frigate's default certificate cannot be verified.** On 8971 it is
  `CN=*` without subject alternative names; no client accepts it, not even
  with the certificate itself as `caCert` (checked live). Replace it, or use
  `skipVerify` through `withTls` on a network you trust. The docs sign in
  with a CA file and say this.
- Caps: `DEFAULT_MAX_BYTES` (16 MiB) for JSON and `DEFAULT_MAX_MEDIA_BYTES`
  (256 MiB) for images and video. Deadline: `DEFAULT_TIMEOUT_MS` (30 s) per
  request, enforced as a hard deadline on a task.
- Server text in messages is cleaned and cut.

## Testing and validation

- `jennifer test src/frigate_test.j` runs against an `httpd` fake on
  loopback that answers canned replies, with fixtures copied from the live
  run, and records requests including the cache-bypass header.
- Live, 2026-11-14: every export and all examples against Frigate 0.18.2 in
  a container (CPU detector, MQTT off, one camera reading a looped test
  video, continuous recording). A second validation pass the same day found
  the nginx cache, the renamed cookie, the heat-map size and the JPEG
  snapshot, all handled now.
- Server checks absent in 0.18.2 (a `detect` value of `"maybe"`, an unknown
  zone) are not imitated by the deck.
- CI runs the examples without arguments (they print usage).

## Known limitations and open questions

- Event changes take effect asynchronously; a read right after a write may
  show the old state.
- A snapshot of a manual event that is still open is 404.
- `restart` in Docker™ exits the container unless it has a restart policy.
- Bodies are read whole; streaming downloads wait for streaming responses in
  `http` (M30.9).

## Dependencies on the interpreter

Floor `>=0.27.0`, capability `net`, for the UTF-8 codec of `encoding.decode`
and `strings.replicate`; it uses the bundled `http` and `uri` modules. From
`jennifer`'s milestones: M28.57 (the error conventions) and M28.65 (transport
failures as `net.NetError`, passed on).
