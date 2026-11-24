# Changelog

## Unreleased

- **The running instance keeps its lock in an ahead-of-time build that never
  calls `SingleInstancePrimary.close`.** The open file holding the lock was
  read only by `close`, so a compiled application that left the claim to the
  process ending had the field removed as unused; the file became
  unreachable, its finalizer closed it within moments of startup, the lock
  went with it, and every later launch became a second running instance
  instead of handing its link over. The JIT keeps every field, so tests run
  with `dart test` never saw it. The held file is now also kept in the
  package's table of locks held in this process until the lock is released.
  `test/multi_process_test.dart` gains `aot` groups that run a helper built
  with `dart compile exe` which never closes its claim.

- **Initial package: a second launch hands its link to the running
  instance.** On Windows and Linux the operating system opens a URL by
  starting the application with the URL as its argument, so every link
  started another process and another window; macOS delivers the URL to the
  running application instead. `SingleInstance.claim` closes the gap: the
  first launch becomes the running instance and receives later launches'
  links on `SingleInstancePrimary.links`; a later launch that carries a link
  hands it over and is told to exit (`SingleInstanceDelivered`); anything
  else runs on its own, as before (`SingleInstanceStandalone`, with the
  reason).
  - The running instance holds an exclusive lock for its lifetime, so the
    operating system releases it when the process ends however it ends, and
    the next launch replaces the socket and the token a dead instance left.
  - Linux and other POSIX hosts listen on a Unix domain socket in
    `$XDG_RUNTIME_DIR/crux-single-instance`, or a `0700` directory under the
    user's cache when the session has no private runtime directory. Windows
    listens on `127.0.0.1` at an ephemeral port named in the user's
    `%LOCALAPPDATA%`. Never on another interface.
  - Both sides prove they hold a per-launch token read from that directory,
    with HMAC-SHA256 over fresh nonces; the token never crosses the socket,
    and a launch sends its link only after the listener has proved itself.
  - `SingleInstanceLinkPolicy` admits exactly one URL of a declared scheme,
    bounded in UTF-8 bytes, on both sides of the socket. Handshake lines are
    bounded too, connections are capped and time out.
