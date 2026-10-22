# crux_single_instance

Single-instance link delivery for the EDACrux desktop apps on Windows and
Linux. Pure Dart (`dart:io`, plus `chmod` through `dart:ffi`), no Flutter.

macOS delivers a URL to the running application. Windows and Linux start a
new process with the URL as its argument, so every link opened another
window. With this package the new process hands its link to the one already
running and exits.

```dart
import 'package:crux_single_instance/crux_single_instance.dart';

// Early in startup, before a window is shown; Windows and Linux only.
final claim = await SingleInstance(
  appId: 'com.example.viewer',
  policy: SingleInstanceLinkPolicy(schemes: const ['viewer']),
).claim(link: linkFromCommandLine); // null for an ordinary launch

switch (claim) {
  case SingleInstanceDelivered():
    exit(0); // the running instance has it
  case SingleInstancePrimary(:final links):
    links.listen(openLink); // later launches' links
    if (linkFromCommandLine != null) openLink(linkFromCommandLine);
  case SingleInstanceStandalone():
    // Run as before, opening this launch's own link if it has one.
    if (linkFromCommandLine != null) openLink(linkFromCommandLine);
}
```

`claim` never throws. A launch without a link never waits: it becomes the
running instance when there is none and opens an ordinary second window when
there is.

## Design

**Rendezvous directory.** Everything happens in one directory only this user
can enter:

| Host | Directory | Listener |
|---|---|---|
| Linux, other POSIX | `$XDG_RUNTIME_DIR/crux-single-instance`, else `${XDG_CACHE_HOME:-~/.cache}/crux-single-instance` | Unix domain socket `<appId>.sock` |
| Windows | `%LOCALAPPDATA%\crux-single-instance` | TCP on `127.0.0.1`, ephemeral port |

On POSIX the directory is set to `0700` and checked afterwards; a runtime
directory with any group or other bit is passed over, and a directory that
still has one after `chmod` is refused (`SingleInstanceStandalone`,
`unavailable`). On Windows the user's profile grants access to the user,
`SYSTEM` and administrators only, and the directory inherits that. `dart:io`
has no Unix domain sockets on Windows, which is why it listens on loopback
there.

**Election.** The running instance holds an exclusive lock on `<appId>.lock`
for its lifetime. A launch that gets the lock is the running instance; one
that does not knows another is running. The operating system releases the
lock when a process ends, however it ends, so **stale-socket recovery** is
mechanical: the lock was free, so the socket and advert in the directory
belong to a dead instance, and the new one deletes them before it binds.
Two launches at once cannot both win, which is what makes **concurrent
launches** safe: one is elected and the others deliver to it, retrying until
it is listening or `timeout` (three seconds by default) runs out.

**Advert.** `<appId>.json` (mode `0600` on POSIX) carries the protocol name, a
fresh 128-bit token, and on Windows the port. It is written beside its final
name and renamed over it, so a reader sees a whole file or none.

**Exchange.** One connection carries one link, in four newline-terminated
lines:

1. launch → `crux-single-instance/1 <client nonce>`
2. running → `<server nonce> HMAC(token, "server:" + cn + ":" + sn)`
3. launch → `HMAC(token, "client:" + cn + ":" + sn + ":" + link) <link>`
4. running → `ok` or `refused`

The token never crosses the socket. The launch checks line 2 before it sends
the link, so a process that took a dead instance's port, and does not hold the
token, never sees a link; the running instance checks line 3, so a process
that cannot read the directory cannot deliver one. Nonces keep either proof
from being replayed, and the link is bound into the client proof.

**What is accepted.** `SingleInstanceLinkPolicy` runs on both sides: exactly
one URL of a declared scheme, no white space or control characters, at most
`maxLinkBytes` (8192 by default) in UTF-8. A launch whose link fails it does
not connect and runs on its own, so the application's own parser reports the
link to the user. The running instance refuses anything else, as it does a
greeting it does not recognise, a line over its bound, a peer that takes more
than five seconds, and a ninth simultaneous connection. Passing the policy says
nothing about what the link asks for; the application still parses it
strictly.

**Trust boundary.** The same as the user's shell: any process running as this
user can read the directory and deliver a link, exactly as it could start the
application with that link. No other account can, and nothing listens beyond
the local machine.

**Limits.** A running instance whose main isolate is blocked answers late; a
launch that times out runs on its own and opens its link itself, so a link is
never lost, only opened in a second window. The same holds on Windows when
another local account fills the eight connection slots on the loopback port:
it can make a link open in a second window, never read or inject one. A Unix socket path must fit the
platform's `sun_path` (about 100 bytes); one that does not makes the launch
run on its own. macOS needs none of this, since the system delivers URLs to
the running application.

## Testing

`directory`, `transport` and `environment` are injectable, so every path runs
in one test process on any host (both transports on POSIX). The
multi-process tests compile `test/support/instance_main.dart` and run it as
real processes, because a lock held by another process, and the operating
system releasing it when that process is killed, cannot be shown inside one.
