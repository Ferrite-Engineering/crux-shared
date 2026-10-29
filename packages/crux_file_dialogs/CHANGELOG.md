# Changelog

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
