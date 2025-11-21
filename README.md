ratrap — blocklisting http stub
-------------------------------------------------------------------------------
%%VERSION%%

ratrap listens on 127.0.0.1, default port 60666 for HTTP requests that contain
`X-Forwarded-For`, and passes those addresses to the BSD `blocklistd` service.

It was written entirely by hand, and is distributed under the ISC license.

Homepage: https://fossil.se30.xyz/ratrap

## Installation

ratrap can be initially installed by cloning its Fossil repo and doing:

    opam switch create .

You can update it later by doing:

    fossil up; and opam install .

If you don't use `opam`, the package builds with `Topkg`, which we'll
assume you can operate, given that you don't use `opam`.

## Synopsis

Start `ratrap` using your favorite service manager. Direct any HTTP request that
annoys you to 127.0.0.1, port 60666, passing the client IP in `X-Forwarded-For`.

Requests that reach the trap are logged to stdout. For requests that include a
body, the logs show up to 240 characters of the content, with non-newline
control characters shown as their Unicode Control Picture form, and non-ASCII
characters replaced with their hex form in C notation (`\x90`).

## Documentation

To deploy this successfully requires modifications to your firewall rules,
`blocklistd` setup, and web server configuration. It has been tested on FreeBSD,
using `pf` and `nginx`.

A basic `pf.conf` follows:

    pass
    anchor "ratrap" {
        anchor "60666" in {
            block in proto tcp from <port60666> to any port {80, 443}
        }
    }

Then, add the relevant stanza in `/etc/blocklistd.conf`:

    # adr/mask:port type    proto   owner       name    nfail   disable
    [local]
    60666           stream  *       *           ratrap  3       10m

Finally, place this stanza or similar in your `nginx` configuration as
appropriate. We have a file `ratrap` in the configuration root and
`include ratrap;` in our `sites-enabled` files.

    location ~* (cgi-bin|\.php$|\.env|/aws|^/service|\.git/config|/wp-|/wordpress/) {
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_pass_request_headers off;
        proxy_pass http://localhost:60666;
    }

## Architecture

The design of `blocklistd` uses the POSIX socket function `getpeername` to find
the address to block, which assumes that your service is directly connected to
the offending socket. This is not the case in the HTTP proxy world, so at first
it would seem difficult to use `blocklistd` without a module in the web server.


It is also the case in the UDP world, though, and it is for this use-case that
`blocklistd` provides the
[`blocklist_sa_r`](https://man.netbsd.org/blocklist_sa_r.3) interface, which
works with an un-connected socket and a client-provided address.

Therefore, in addition to the actual server socket, `ratrap` creates two control
sockets, one for IPv4 and another for IPv6, and binds them but does not listen
on them. They remain un-connected, and so we can pass along the address coming
from the `X-Forwarded-For` header. We need a socket for IPv4 and IPv6 because
`blocklistd` aborts if the socket type does not match the address type.

## Example

From one of our servers:

    ==> /var/log/nginx/whatdoescismean.com-access.log <==
    204.76.203.25 - - [15/Nov/2025:19:51:08 +0000] "GET /.env HTTP/1.1" 404 0 "-" "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.3" "-"

    ==> /var/log/ratrap/current <==
    2025-11-15_19:51:08.28757 Connection from tcp:127.0.0.1:40513
    2025-11-15_19:51:08.28760 GET /.env
    2025-11-15_19:51:08.28760 Host: whatdoescismean.com
    2025-11-15_19:51:08.28760 X-Forwarded-For: 204.76.203.25
    2025-11-15_19:51:08.28760 Connection: close
    2025-11-15_19:51:08.28761
    2025-11-15_19:51:08.28761
    2025-11-15_19:51:08.28762 +Blocklisting 204.76.203.25
    2025-11-15_19:51:08.28773 ---
    2025-11-15_19:51:08.28830 +successfully blocklisted

    ==> /var/log/daemon.log <==
    Nov 15 19:51:08 bung blacklistd[32820]: blocked 204.76.203.25/32:60666 for 600 seconds


## Bugs

The C function bindings actually use the legacy `blacklist` spelling because
FreeBSD-14.3 does not use the renamed package from NetBSD upstream. If you
deploy this on NetBSD, you'll have to edit the Ctypes bindings in
`src/blocklist.ml` accordingly.

There are no tests.

The package also builds (but does nothing) on macOS using an undocumented stub library.
