# crux_file_dialogs

File dialogs on Linux that work on a remote display.

## The problem

file_picker 12's Linux implementation draws every dialog through the XDG
desktop portal (`org.freedesktop.portal.FileChooser`) over the DBus session
bus, and has no fallback. It fails whenever the session bus is unreachable or
has no portal, which is how Linux GUIs are usually run in an engineering
organization:

- a session started on one host and run on another (a farm job copies the
  environment, so `DBUS_SESSION_BUS_ADDRESS` names a socket on the submitting
  host);
- a remote X session (ssh X forwarding, VNC, ETX, NX) with no desktop on the
  machine;
- a RHEL or Rocky host without `xdg-desktop-portal-gtk`.

Every Open, Save and Export then fails with a `SocketException`. Where a bus
is reachable it can belong to the desktop on the machine's console, and the
portal draws the dialog on that screen instead of the one the app is on.

## The fix, in two halves

**Runner (C++).** `native/linux/crux_file_dialogs.cc` serves the
`crux/file_dialog` method channel with a `GtkFileChooserDialog` drawn in the
app's own process, on the display its window is on. Methods `open`, `save`
and `directory`; the answer is the list of chosen paths, empty on cancel.
Saving asks before overwriting, and an extension filter matches any letter
case. It also installs `crux_tolerate_refused_x_bell`: under `ssh -X` the X
server refuses the alert sound with `BadAccess`, GDK's default handler ends
the process on it, and the chooser rings the bell itself.

Every product's Linux runner, the open core's and the Pro overlay's, compiles
the file from this package and calls both functions after
`fl_register_plugins`:

```cmake
# linux/CMakeLists.txt
pkg_check_modules(X11 REQUIRED IMPORTED_TARGET x11)

# linux/runner/CMakeLists.txt (an open core; a Pro overlay reaches the same
# file through its open-core submodule)
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${CMAKE_SOURCE_DIR}/../crux-shared/packages/crux_file_dialogs/native/linux/crux_file_dialogs.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::X11)
target_include_directories(${BINARY_NAME} PRIVATE
  "${CMAKE_SOURCE_DIR}/../crux-shared/packages/crux_file_dialogs/native/linux")
```

```c++
// linux/runner/my_application.cc, in my_application_activate
fl_register_plugins(FL_PLUGIN_REGISTRY(view));
crux_register_file_dialog_channel(view);
crux_tolerate_refused_x_bell("Product");
```

It is a source file the runner compiles, not a Flutter plugin, so a product
opts in where its runner is written and a static test can see it.

**Dart.** `GtkFilePicker` is a `FilePickerPlatform` that sends file_picker's
calls to that channel. `useGtkFileDialogsOnLinux()` installs it on Linux and
does nothing elsewhere; each product's `bootstrap()` calls it once the binding
is initialized. When the runner does not serve the channel the call raises
`MissingPluginException`, and the picker hands it to file_picker's own
implementation, so a build without the runner half behaves as before.

`GtkFileChooserNative` would not do: it goes through the same portal when
`GTK_USE_PORTAL` is set, and inside a Flatpak or Snap sandbox.

## Guarding it

`crux_file_dialogs_guards.dart` exports `cruxCheckLinuxRunnerFileDialogs`,
plain string checks over `my_application.cc` and the two `CMakeLists.txt`
files. Each product runs it from a `test/static/` test, for its open-core and
its Pro runner alike, so a runner that loses the call fails a unit test rather
than a user on a remote display. Each product's Linux launch test opens the
picker under Xvfb with no reachable session bus and finds the GTK dialog's
window.
