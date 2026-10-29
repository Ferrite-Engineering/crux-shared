// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

#include "crux_file_dialogs.h"

#include <cstring>

#ifdef GDK_WINDOWING_X11
#include <X11/Xlib.h>
#include <X11/Xproto.h>
#include <gdk/gdkx.h>
#endif

#ifdef GDK_WINDOWING_X11
// The handler GDK installed, which every other error still goes to.
static XErrorHandler gdk_x_error_handler = nullptr;
// The XKEYBOARD extension's major opcode, or -1 when the server lacks it.
static int xkb_major_opcode = -1;
// X_kbBell, from XKBproto.h.
constexpr int kXkbBellMinorOpcode = 3;
// Names the app in the one line written when the bell is first refused.
static gchar* bell_app_name = nullptr;

static int handle_x_error(Display* display, XErrorEvent* event) {
  const bool bell = event->request_code == X_Bell ||
                    (xkb_major_opcode > 0 &&
                     event->request_code == xkb_major_opcode &&
                     event->minor_code == kXkbBellMinorOpcode);
  // GDK never sends a bell inside an error trap, so nothing is waiting to
  // collect this error, and dropping it loses only the sound.
  if (bell && event->error_code == BadAccess) {
    static bool reported = false;
    if (!reported) {
      reported = true;
      g_printerr(
          "%s: the X server refused the alert sound, as it does for an "
          "untrusted client such as ssh -X; continuing without it.\n",
          bell_app_name != nullptr ? bell_app_name : "crux");
    }
    return 0;
  }
  return gdk_x_error_handler != nullptr ? gdk_x_error_handler(display, event)
                                        : 0;
}
#endif

void crux_tolerate_refused_x_bell(const gchar* app_name) {
#ifdef GDK_WINDOWING_X11
  GdkDisplay* display = gdk_display_get_default();
  if (display == nullptr || !GDK_IS_X11_DISPLAY(display)) {
    return;
  }
  // Installed once: a second call would chain the handler to itself.
  static bool installed = false;
  if (installed) {
    return;
  }
  installed = true;
  bell_app_name = g_strdup(app_name);
  int first_event = 0;
  int first_error = 0;
  if (!XQueryExtension(GDK_DISPLAY_XDISPLAY(display), "XKEYBOARD",
                       &xkb_major_opcode, &first_event, &first_error)) {
    xkb_major_opcode = -1;
  }
  gdk_x_error_handler = XSetErrorHandler(handle_x_error);
#else
  (void)app_name;
#endif
}

// Returns the string argument [key], or nullptr when it is absent or null.
static const gchar* string_argument(FlValue* args, const gchar* key) {
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(value);
}

// Returns a glob matching "*.<extension>" in any letter case, since GTK
// patterns are case-sensitive and design files arrive as both top.v and TOP.V.
static gchar* case_insensitive_pattern(const gchar* extension) {
  GString* pattern = g_string_new("*.");
  for (const gchar* c = extension; *c != '\0'; c++) {
    if (g_ascii_isalpha(*c)) {
      g_string_append_printf(pattern, "[%c%c]", g_ascii_tolower(*c),
                             g_ascii_toupper(*c));
    } else {
      g_string_append_c(pattern, *c);
    }
  }
  return g_string_free(pattern, FALSE);
}

// Adds one filter accepting every extension in [extensions], named after
// them ("*.v, *.sv"), when the caller asked for any.
static void add_extension_filter(GtkFileChooser* chooser, FlValue* extensions) {
  if (extensions == nullptr ||
      fl_value_get_type(extensions) != FL_VALUE_TYPE_LIST ||
      fl_value_get_length(extensions) == 0) {
    return;
  }
  GtkFileFilter* filter = gtk_file_filter_new();
  GString* name = g_string_new(nullptr);
  for (size_t i = 0; i < fl_value_get_length(extensions); i++) {
    FlValue* item = fl_value_get_list_value(extensions, i);
    if (fl_value_get_type(item) != FL_VALUE_TYPE_STRING) {
      continue;
    }
    const gchar* extension = fl_value_get_string(item);
    g_autofree gchar* pattern = case_insensitive_pattern(extension);
    gtk_file_filter_add_pattern(filter, pattern);
    g_string_append_printf(name, "%s*.%s", name->len > 0 ? ", " : "",
                           extension);
  }
  gtk_file_filter_set_name(filter, name->str);
  g_string_free(name, TRUE);
  // The chooser takes ownership of the floating reference.
  gtk_file_chooser_add_filter(chooser, filter);
}

// Shows one chooser and answers with the chosen paths, an empty list when the
// user cancels. Methods: "open" (title, folder, multiple, extensions), "save"
// (title, folder, name, extensions) and "directory" (title, folder).
static void file_dialog_method_call(FlMethodChannel* channel,
                                    FlMethodCall* method_call,
                                    gpointer user_data) {
  FlView* view = FL_VIEW(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    fl_method_call_respond_error(method_call, "bad-arguments",
                                 "expected a map of arguments", nullptr,
                                 nullptr);
    return;
  }

  GtkFileChooserAction action;
  const gchar* default_title;
  const gchar* accept_label;
  if (strcmp(method, "open") == 0) {
    action = GTK_FILE_CHOOSER_ACTION_OPEN;
    default_title = "Open";
    accept_label = "_Open";
  } else if (strcmp(method, "save") == 0) {
    action = GTK_FILE_CHOOSER_ACTION_SAVE;
    default_title = "Save";
    accept_label = "_Save";
  } else if (strcmp(method, "directory") == 0) {
    action = GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER;
    default_title = "Choose Folder";
    accept_label = "_Select";
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
    return;
  }

  const gchar* title = string_argument(args, "title");
  GtkWindow* parent = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  // A GtkFileChooserDialog, not a GtkFileChooserNative: the native variant
  // goes through the same portal when GTK_USE_PORTAL is set, and this must not.
  GtkWidget* dialog = gtk_file_chooser_dialog_new(
      title != nullptr ? title : default_title, parent, action, "_Cancel",
      GTK_RESPONSE_CANCEL, accept_label, GTK_RESPONSE_ACCEPT, nullptr);
  GtkFileChooser* chooser = GTK_FILE_CHOOSER(dialog);
  gtk_window_set_modal(GTK_WINDOW(dialog), TRUE);

  const gchar* folder = string_argument(args, "folder");
  if (folder != nullptr) {
    gtk_file_chooser_set_current_folder(chooser, folder);
  }
  if (action == GTK_FILE_CHOOSER_ACTION_OPEN) {
    FlValue* multiple = fl_value_lookup_string(args, "multiple");
    gtk_file_chooser_set_select_multiple(
        chooser, multiple != nullptr &&
                     fl_value_get_type(multiple) == FL_VALUE_TYPE_BOOL &&
                     fl_value_get_bool(multiple));
  }
  if (action == GTK_FILE_CHOOSER_ACTION_SAVE) {
    gtk_file_chooser_set_do_overwrite_confirmation(chooser, TRUE);
    const gchar* name = string_argument(args, "name");
    if (name != nullptr) {
      gtk_file_chooser_set_current_name(chooser, name);
    }
  }
  if (action != GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER) {
    add_extension_filter(chooser, fl_value_lookup_string(args, "extensions"));
  }

  g_autoptr(FlValue) paths = fl_value_new_list();
  if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
    GSList* files = gtk_file_chooser_get_filenames(chooser);
    for (GSList* file = files; file != nullptr; file = file->next) {
      fl_value_append_take(paths,
                           fl_value_new_string(static_cast<gchar*>(file->data)));
    }
    g_slist_free_full(files, g_free);
  }
  gtk_widget_destroy(dialog);

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond_success(method_call, paths, &error)) {
    g_warning("Failed to answer the file dialog call: %s", error->message);
  }
}

void crux_register_file_dialog_channel(FlView* view) {
  // Lives as long as the process: there is one window and one engine.
  static FlMethodChannel* channel = nullptr;
  if (channel != nullptr) {
    return;
  }
  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel = fl_method_channel_new(fl_engine_get_binary_messenger(engine),
                                  CRUX_FILE_DIALOG_CHANNEL,
                                  FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, file_dialog_method_call,
                                            view, nullptr);
}
