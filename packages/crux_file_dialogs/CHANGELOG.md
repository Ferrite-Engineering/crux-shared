# Changelog

## Unreleased

- `crux_select_renderer_for_display`: the renderer probe every runner kept its
  own copy of, now shared, and it also picks the software renderer when the X
  display names another host (a farm job on an ETX or VNC server, ssh X
  forwarding). There OpenGL often works, but every frame crosses the network
  (netcrux#39).
- `crux_skip_accessibility_bridge_without_session_bus`: sets `NO_AT_BRIDGE`
  before GTK starts when no DBus session bus is reachable.
- `cruxCheckLinuxRunnerFileDialogs` now requires both: the renderer choice
  before `fl_view_new`, the bridge check in `my_application_new`.
- `crux_prefer_x11_when_only_display_is_set`: limits GTK to X11 when
  `DISPLAY` is set and `WAYLAND_DISPLAY` is not, so over ssh X forwarding to
  a machine where the same user is also logged in to a Wayland desktop the
  window opens on the forwarded display, not on that machine's own screen. A
  `GDK_BACKEND` the user has set is left alone. `cruxCheckLinuxRunnerFileDialogs`
  requires it in `my_application_new`, before the bridge check.

## 0.1.0

- Initial release, lifted from NetCrux, where it shipped first. `GtkFilePicker`
  sends file_picker's Linux calls to the runner's `crux/file_dialog` channel,
  falling back to file_picker's own implementation when the runner does not
  serve it; `useGtkFileDialogsOnLinux` installs it.
- `native/linux/crux_file_dialogs.cc`: the channel, an in-process
  `GtkFileChooserDialog` on the window's own display, and
  `crux_tolerate_refused_x_bell`, which keeps an untrusted X client alive when
  the server refuses the alert sound.
- `cruxCheckLinuxRunnerFileDialogs`, the static check each product runs over
  its Linux runner.
- Beyond NetCrux's copy: the media file types filter by file_picker's own
  extension lists, `withReadStream` is honoured, and the bell line names the
  product it is passed.
