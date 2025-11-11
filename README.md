ratrap — blocklisting http stub
-------------------------------------------------------------------------------
%%VERSION%%

ratrap listens on 127.0.0.1, port 60666 for HTTP requests that contain
`X-Forwarded_For`, and passes those addresses to the BSD `blocklistd` service.

It was written entirely by hand, and is distributed under the ISC license.

Homepage: https://fossil.se30.xyz/ratrap

## Installation

ratrap can be installed with `opam`:

    opam install ratrap

If you don't use `opam`, the package builds with `Topkg`, which we'll
assume you can operate, given that you don't use `opam`.

## Synopsis

Start `ratrap` using your favorite service manager. Direct any HTTP request that
annoys you to 127.0.0.1, port 60666.

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
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header Content-Length "";
        proxy_pass_request_headers off;
        proxy_pass_request_body off;
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

## Bugs

While the binding port 60666 is a `ref` in the code, there is no way to change
the port without editing the code yet.

The C function bindings actually use the legacy `blacklist` spelling because
FreeBSD-14.3 does not use the renamed package from NetBSD upstream. If you
deploy this on NetBSD, you'll have to edit the Ctypes bindings in
`src/blocklist.ml` accordingly.
