/*
 * Chromium 140+ (Jan 2026, crbug 470928605) builds GTK file-chooser dialogs
 * with a custom accept response id (0) and then:
 *
 *   gtk_dialog_set_default_response(dialog, GTK_RESPONSE_CANCEL);
 *
 * so a held Enter cannot confirm a file the page pre-selected. GtkFileChooser
 * also activates the *default* button on double-click and Enter, so both
 * cancel the dialog. Clicking Open still works because that button's response
 * is 0, not CANCEL.
 *
 * Chromium resolves GTK via dlopen/dlsym (not a DT_NEEDED on the ELF), so this
 * library is LD_PRELOAD'd and intercepts dlsym("gtk_dialog_set_default_response").
 * When Chromium asks for Cancel as the default and the dialog has a response-0
 * button (its accept), we set that button as default instead.
 *
 * Disable: CHROMIUM_FILE_DIALOG_DEFAULT=cancel
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

enum { GTK_RESPONSE_CANCEL = -6 };

typedef void *(*dlsym_fn)(void *handle, const char *symbol);
typedef void (*set_default_fn)(void *dialog, int response_id);
typedef void *(*get_widget_fn)(void *dialog, int response_id);

static dlsym_fn real_dlsym;
static set_default_fn real_set_default;
static get_widget_fn real_get_widget;

static int fix_enabled(void) {
  const char *e = getenv("CHROMIUM_FILE_DIALOG_DEFAULT");
  if (e == NULL || e[0] == '\0')
    return 1;
  return strcmp(e, "cancel") != 0 && strcmp(e, "0") != 0 &&
         strcmp(e, "off") != 0 && strcmp(e, "no") != 0 &&
         strcmp(e, "false") != 0;
}

static void resolve_real_dlsym(void) {
  if (real_dlsym)
    return;
  /* x86_64 glibc: dlsym@GLIBC_2.2.5 and @@GLIBC_2.34. aarch64: GLIBC_2.17. */
  static const char *vers[] = {"GLIBC_2.34", "GLIBC_2.17", "GLIBC_2.2.5", NULL};
  int i;
  for (i = 0; vers[i]; i++) {
    real_dlsym = (dlsym_fn)dlvsym(RTLD_NEXT, "dlsym", vers[i]);
    if (real_dlsym)
      return;
  }
}

static void wrapped_set_default(void *dialog, int response_id) {
  if (fix_enabled() && dialog && response_id == GTK_RESPONSE_CANCEL &&
      real_get_widget) {
    /* Chromium's accept button uses application response id 0. */
    if (real_get_widget(dialog, 0))
      response_id = 0;
  }
  if (real_set_default)
    real_set_default(dialog, response_id);
}

void *dlsym(void *handle, const char *symbol) {
  void *real;

  resolve_real_dlsym();
  if (!real_dlsym)
    return NULL;

  /* Never intercept our own RTLD_NEXT lookups. */
  if (symbol && handle != RTLD_NEXT &&
      strcmp(symbol, "gtk_dialog_set_default_response") == 0) {
    real = real_dlsym(handle, symbol);
    if (real) {
      real_set_default = (set_default_fn)real;
      if (handle && handle != RTLD_DEFAULT)
        real_get_widget =
            (get_widget_fn)real_dlsym(handle,
                                      "gtk_dialog_get_widget_for_response");
      else
        real_get_widget =
            (get_widget_fn)real_dlsym(RTLD_DEFAULT,
                                      "gtk_dialog_get_widget_for_response");
      return (void *)wrapped_set_default;
    }
    return NULL;
  }

  return real_dlsym(handle, symbol);
}
