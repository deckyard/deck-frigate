<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Signing in

Frigate serves its API on two ports:

| Port | Scheme | Sign-in | Use |
|---|---|---|---|
| 8971 | https | user name and password | the normal way in |
| 5000 | http | none, every request is admin | inside the host or a trusted network, only where the operator published it |

The base URL is the server's root, without `/api`:

```jennifer
def c as frigate.Client init frigate.client("https://nvr.example.org:8971");
$c = frigate.login($c, "admin", os.getEnv("FRIGATE_PASSWORD"));
io.printf("%s, %s\n", frigate.profile($c).username, frigate.version($c));
```

`login` posts the name and password and keeps the JWT the server sets as its
`frigate_token` cookie (or the cookie `auth.cookie_name` names instead); the
deck sends it as a bearer token. A refused
password is `HttpError` status 401; where the operator set
`auth.failed_login_rate_limit`, too many attempts are status 429.

## Keeping the token

The token is in `Client.token` and works until it expires, after the
server's `auth.session_length` (24 hours by default). A program that runs
often can keep it instead of signing in each time:

```jennifer
$c = frigate.withToken(frigate.client($url), $saved);
```

A token past its time is `HttpError` status 401 on the next call; sign in
again then. There is no logout: Frigate keeps no session to end, and its
`/logout` only clears the browser's cookie. A token stays valid until it
expires, so keep it like the password.

## The unauthenticated port

Port 5000 needs no sign-in (`profile` says `anonymous`, role `admin`).
It is plain http, which the deck refuses except to this machine; on the LAN
add `withPlainHttp`:

```jennifer
def c as frigate.Client init frigate.withPlainHttp(frigate.client("http://nvr.lan:5000"));
```

`examples/status.j` does that with `FRIGATE_PLAIN=1`.

## Certificates

Until the operator installs a certificate, port 8971 serves Frigate's own,
which names no host (`CN=*`, no subject alternative names). No TLS client
can verify it, not even with the certificate itself as `caCert`, so
reaching it takes `skipVerify`:

```jennifer
$c = frigate.withTls($c, http.TlsOptions{skipVerify: true});
```

That turns off the check that the server is the one meant, so only use it
on a network you trust. With a certificate from a private CA, trust the CA
instead: `http.TlsOptions{caCert: fs.readBytes("ca.pem")}`. `http` is the
bundled module (`import "http.j" as http;`).

## Limits

`withTimeout` sets the deadline of each request (30 s by default),
`withMaxBytes` the cap on JSON responses (16 MiB), `withMaxMediaBytes` the
cap on images and video (256 MiB). A long clip or export can need more:
media is read into memory whole.
