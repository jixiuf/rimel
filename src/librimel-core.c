#include <rime_api.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <unistd.h>

#include "interface.h"
#include "librimel-core.h"

/**
 * Macro that defines a docstring for a function.
 * @param name The function name (without librimel_ prefix).
 * @param args The argument list as visible from Emacs (without parens).
 * @param docstring The rest of the documentation.
 */
#define DOCSTRING(name, args, docstring)                                       \
  const char *name##__doc = (docstring "\n\n(fn " args ")")

#define DEFUN(ename, cname, min_nargs, max_nargs)                              \
  em_defun(env, (ename),                                                       \
           env->make_function(env, (min_nargs), (max_nargs), cname,            \
                              cname##__doc, rime))

#define CONS_INT(key, integer)                                                 \
  em_cons(env, env->intern(env, key), env->make_integer(env, integer));
#define CONS_STRING(key, str)                                                  \
  em_cons(env, env->intern(env, key), env->make_string(env, str, strlen(str)))
#define CONS_NIL(key) em_cons(env, env->intern(env, key), em_nil)
#define CONS_VALUE(key, value) em_cons(env, env->intern(env, key), value)

#define CANDIDATE_MAXSTRLEN 1024
#define SCHEMA_MAXSTRLEN 1024
#define CONFIG_MAXSTRLEN 1024
#define INPUT_MAXSTRLEN 1024

#define NO_SESSION_ERR                                                         \
  "Cannot connect to librime session, make sure to run librimel-start first."

typedef struct _EmacsRime {
  RimeSessionId session_id;
  RimeApi *api;
  bool first_run;
} EmacsRime;

typedef struct _CandidateLinkedList {
  char *text;
  char *comment;
  struct _CandidateLinkedList *next;
} CandidateLinkedList;

typedef struct _EmacsRimeCandidates {
  size_t size;
  CandidateLinkedList *list;
} EmacsRimeCandidates;

void notification_handler(void *context, RimeSessionId session_id,
                          const char *message_type, const char *message_value) {
  /* EmacsRime *rime = (EmacsRime*) context; */
  /* emacs_env *env = rime->EmacsEnv; */
  /* char format[] = "[librimel] %s: %s"; */
  /* emacs_value args[3]; */
  /* args[0] = env->make_string(env, format, strnlen(format, SCHEMA_MAXSTRLEN));
   */
  /* args[1] = env->make_string(env, message_type, strnlen(message_type,
   * SCHEMA_MAXSTRLEN)); */
  /* args[2] = env->make_string(env, message_value, strnlen(message_value,
   * SCHEMA_MAXSTRLEN)); */
  /* env->funcall(env, env->intern (env, "message"), 3, args); */
}

// Get session_id from args. If not provided or nil, use default session_id.
// Returns the session_id to use.
static RimeSessionId _get_session(EmacsRime *rime, emacs_env *env,
                                  ptrdiff_t nargs, emacs_value args[],
                                  int arg_index) {
  // If session_id argument is provided and not nil, use it
  if (nargs > arg_index && env->is_not_nil(env, args[arg_index])) {
    return (RimeSessionId)env->extract_integer(env, args[arg_index]);
  }
  // Otherwise use default session
  return rime->session_id;
}

// Ensure the given session exists
static bool _ensure_given_session(EmacsRime *rime, RimeSessionId session_id) {
  if (!rime->api->find_session(session_id)) {
    return false;
  }
  return true;
}

static char *_copy_string(char *str) {
  if (str) {
    size_t size = strnlen(str, CANDIDATE_MAXSTRLEN);
    char *new_str = malloc(size + 1);
    strncpy(new_str, str, size);
    new_str[size] = '\0';
    return new_str;
  } else {
    return NULL;
  }
}

EmacsRimeCandidates _get_candidates(EmacsRime *rime, RimeSessionId session_id,
                                    size_t limit) {
  EmacsRimeCandidates c = {
      .size = 0,
      .list = (CandidateLinkedList *)malloc(sizeof(CandidateLinkedList))};

  RimeCandidateListIterator iterator = {0};
  CandidateLinkedList *next = c.list;
  if (rime->api->candidate_list_begin(session_id, &iterator)) {
    while (rime->api->candidate_list_next(&iterator) &&
           (limit == 0 || c.size < limit)) {
      c.size += 1;

      next->text = _copy_string(iterator.candidate.text);
      next->comment = _copy_string(iterator.candidate.comment);

      next->next = (CandidateLinkedList *)malloc(sizeof(CandidateLinkedList));

      next = next->next;
    }
    next->next = NULL;
    rime->api->candidate_list_end(&iterator);
  }

  return c;
}

// bindings
DOCSTRING(librimel_start, "SHARED_DATA_DIR USER_DATA_DIR",
          "Start a rime session.");
static emacs_value librimel_start(emacs_env *env, ptrdiff_t nargs,
                                  emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;

  char *shared_data_dir = em_get_string(env, em_expand_file_name(env, args[0]));
  char *user_data_dir = em_get_string(env, em_expand_file_name(env, args[1]));

  RIME_STRUCT(RimeTraits, emacs_rime_traits);

  emacs_rime_traits.shared_data_dir = shared_data_dir;
  emacs_rime_traits.app_name = "rime.emacs-librimel";
  emacs_rime_traits.user_data_dir = user_data_dir;
  emacs_rime_traits.distribution_name = "Rime";
  emacs_rime_traits.distribution_code_name = "emacs-librimel";
  emacs_rime_traits.distribution_version = "0.1.0";
  if (rime->first_run) {
    rime->api->setup(&emacs_rime_traits);
    rime->first_run = false;
  }

  rime->api->initialize(&emacs_rime_traits);
  rime->api->set_notification_handler(notification_handler, rime);
  rime->api->start_maintenance(true);

  // wait for deploy
  rime->api->join_maintenance_thread();

  if (rime->session_id) {
    rime->api->destroy_session(rime->session_id);
    rime->session_id = 0;
  }
  rime->session_id = rime->api->create_session();

  // Free allocated strings
  free(shared_data_dir);
  free(user_data_dir);

  // Return the session_id
  return env->make_integer(env, rime->session_id);
}

DOCSTRING(librimel_finalize, "", "Finalize librime for redeploy.");
static emacs_value librimel_finalize(emacs_env *env, ptrdiff_t nargs,
                                     emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;
  if (rime->session_id) {
    rime->api->destroy_session(rime->session_id);
    rime->session_id = 0;
  }
  rime->api->finalize();
  return em_t;
}

DOCSTRING(librimel_create_session, "",
          "Create a new rime session and return its id.");
static emacs_value librimel_create_session(emacs_env *env, ptrdiff_t nargs,
                                           emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;
  RimeSessionId new_session_id = rime->api->create_session();
  if (new_session_id) {
    return env->make_integer(env, new_session_id);
  }
  return em_nil;
}

DOCSTRING(
    librimel_destroy_session, "SESSION_ID",
    "Destroy a rime session.\n"
    "Note: Cannot destroy the default session created by librimel-start.");
static emacs_value librimel_destroy_session(emacs_env *env, ptrdiff_t nargs,
                                            emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;
  RimeSessionId session_id = (RimeSessionId)env->extract_integer(env, args[0]);

  // Prevent destroying the default session
  if (session_id == rime->session_id) {
    em_signal_rimeerr(
        env, 1,
        "Cannot destroy the default session created by librimel-start.");
    return em_nil;
  }

  if (rime->api->destroy_session(session_id)) {
    return em_t;
  }
  return em_nil;
}

void free_candidate_list(CandidateLinkedList *list) {
  CandidateLinkedList *next = list;
  while (next) {
    CandidateLinkedList *temp = next;
    next = temp->next;
    // do not free temp->value
    // it seems emacs_env->make_string didn't do copy
    /* if (temp->value) { */
    /*    free(temp->value); */
    /* } */
    free(temp);
  }
}

DOCSTRING(librimel_search, "STRING &optional LIMIT SESSION-ID",
          "Input STRING and return LIMIT number candidates.\n"
          "When LIMIT is nil, return all candidates.\n"
          "When SESSION-ID is provided, use that session.");
static emacs_value librimel_search(emacs_env *env, ptrdiff_t nargs,
                                   emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;
  char *string = em_get_string(env, args[0]);

  size_t limit = 0;
  if (nargs >= 2 && env->is_not_nil(env, args[1])) {
    limit = env->extract_integer(env, args[1]);
    // if limit set to 0 return nil immediately
    if (limit == 0) {
      free(string);
      return em_nil;
    }
  }

  // Get session_id from args (index 2)
  RimeSessionId session_id = _get_session(rime, env, nargs, args, 2);

  if (!_ensure_given_session(rime, session_id)) {
    em_signal_rimeerr(env, 1, NO_SESSION_ERR);
    free(string);
    return em_nil;
  }

  rime->api->clear_composition(session_id);
  rime->api->simulate_key_sequence(session_id, string);

  EmacsRimeCandidates candidates = _get_candidates(rime, session_id, limit);

  // printf("%s: find candidates size: %ld\n", string, candidates.size);
  // return nil if no candidates found
  if (candidates.size == 0) {
    free_candidate_list(candidates.list);
    free(string);
    return em_nil;
  }

  emacs_value *array = malloc(sizeof(emacs_value) * candidates.size);

  CandidateLinkedList *next = candidates.list;
  int i = 0;
  while (next && i < candidates.size) {
    emacs_value value = env->make_string(env, next->text, strlen(next->text));
    if (next->comment) {
      emacs_value comment =
          env->make_string(env, next->comment, strlen(next->comment));
      value = em_propertize(env, value, ":comment", comment);
    }
    array[i++] = value;
    next = next->next;
  }
  // printf("conveted array size: %d\n", i);

  emacs_value result = em_list(env, candidates.size, array);

  // free(candidates.candidates);
  free_candidate_list(candidates.list);
  free(array);
  free(string);

  return result;
}

DOCSTRING(librimel_get_sync_dir, "", "Get rime sync directory.");
static emacs_value librimel_get_sync_dir(emacs_env *env, ptrdiff_t nargs,
                                         emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;

  const char *sync_dir = rime->api->get_sync_dir();
  return env->make_string(env, sync_dir, strlen(sync_dir));
}

DOCSTRING(librimel_sync_user_data, "", "Sync rime user data.");
static emacs_value librimel_sync_user_data(emacs_env *env, ptrdiff_t nargs,
                                           emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;

  bool result = rime->api->sync_user_data();
  return result ? em_t : em_nil;
}

DOCSTRING(librimel_get_schema_list, "", "List all rime schema.");
static emacs_value librimel_get_schema_list(emacs_env *env, ptrdiff_t nargs,
                                            emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;

  RimeSchemaList schema_list;
  if (!rime->api->get_schema_list(&schema_list)) {
    em_signal_rimeerr(env, 1, "Get schema list form librime failed.");
    return em_nil;
  }

  emacs_value flist = env->intern(env, "list");
  emacs_value array[schema_list.size];
  for (int i = 0; i < schema_list.size; i++) {
    RimeSchemaListItem item = schema_list.list[i];
    emacs_value pair[2];
    pair[0] = env->make_string(env, item.schema_id,
                               strnlen(item.schema_id, SCHEMA_MAXSTRLEN));
    pair[1] =
        env->make_string(env, item.name, strnlen(item.name, SCHEMA_MAXSTRLEN));

    array[i] = env->funcall(env, flist, 2, pair);
  }

  emacs_value result = env->funcall(env, flist, schema_list.size, array);

  rime->api->free_schema_list(&schema_list);

  return result;
}

DOCSTRING(
    librimel_select_schema, "SCHEMA-ID &optional SESSION-ID",
    "Select a rime schema.\n"
    "SCHENA-ID should be a value returned from `librimel-get-schema-list'.\n"
    "When SESSION-ID is provided, use that session.");
static emacs_value librimel_select_schema(emacs_env *env, ptrdiff_t nargs,
                                          emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;
  const char *schema_id = em_get_string(env, args[0]);
  RimeSessionId session_id = _get_session(rime, env, nargs, args, 1);

  if (!_ensure_given_session(rime, session_id)) {
    em_signal_rimeerr(env, 1, NO_SESSION_ERR);
    free((char *)schema_id);
    return em_nil;
  }

  RimeSchemaList schema_list;
  if (!rime->api->get_schema_list(&schema_list)) {
    em_signal_rimeerr(env, 1, "Get schema list from librime failed.");
    free((char *)schema_id);
    return em_nil;
  }

  bool found = false;
  for (int i = 0; i < schema_list.size; i++) {
    if (strcmp(schema_list.list[i].schema_id, schema_id) == 0) {
      found = true;
      break;
    }
  }
  rime->api->free_schema_list(&schema_list);

  if (!found) {
    free((char *)schema_id);
    return em_nil;
  }

  bool result = rime->api->select_schema(session_id, schema_id);
  free((char *)schema_id);

  if (result) {
    return em_t;
  }
  return em_nil;
}

// input
DOCSTRING(librimel_process_key, "KEYCODE &optional MASK SESSION-ID",
          "Send KEYCODE to rime session and process it.\n"
          "When SESSION-ID is provided, use that session.");
static emacs_value librimel_process_key(emacs_env *env, ptrdiff_t nargs,
                                        emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;

  int keycode = env->extract_integer(env, args[0]);
  int mask = 0;
  if (nargs >= 2 && env->is_not_nil(env, args[1])) {
    mask = env->extract_integer(env, args[1]);
  }

  RimeSessionId session_id = _get_session(rime, env, nargs, args, 2);

  if (!_ensure_given_session(rime, session_id)) {
    em_signal_rimeerr(env, 1, NO_SESSION_ERR);
    return em_nil;
  }

  if (rime->api->process_key(session_id, keycode, mask)) {
    return em_t;
  }
  return em_nil;
}

DOCSTRING(librimel_get_input, "&optional SESSION-ID",
          "Get rime input.\n"
          "When SESSION-ID is provided, use that session.");
static emacs_value librimel_get_input(emacs_env *env, ptrdiff_t nargs,
                                      emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;

  RimeSessionId session_id = _get_session(rime, env, nargs, args, 0);

  if (!_ensure_given_session(rime, session_id)) {
    em_signal_rimeerr(env, 1, NO_SESSION_ERR);
    return em_nil;
  }

  const char *input = rime->api->get_input(session_id);

  if (!input) {
    return em_nil;
  } else {
    return env->make_string(env, input, strnlen(input, INPUT_MAXSTRLEN));
  }
}

DOCSTRING(librimel_commit_composition, "&optional SESSION-ID",
          "Commit rime composition.\n"
          "When SESSION-ID is provided, use that session.");
static emacs_value librimel_commit_composition(emacs_env *env, ptrdiff_t nargs,
                                               emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;

  RimeSessionId session_id = _get_session(rime, env, nargs, args, 0);

  if (!_ensure_given_session(rime, session_id)) {
    em_signal_rimeerr(env, 1, NO_SESSION_ERR);
    return em_nil;
  }

  if (rime->api->commit_composition(session_id)) {
    return em_t;
  }
  return em_nil;
}

DOCSTRING(librimel_clear_composition, "&optional SESSION-ID",
          "Clear rime composition.\n"
          "When SESSION-ID is provided, use that session.");
static emacs_value librimel_clear_composition(emacs_env *env, ptrdiff_t nargs,
                                              emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;

  RimeSessionId session_id = _get_session(rime, env, nargs, args, 0);

  if (!_ensure_given_session(rime, session_id)) {
    em_signal_rimeerr(env, 1, NO_SESSION_ERR);
    return em_nil;
  }

  rime->api->clear_composition(session_id);
  return em_t;
}

DOCSTRING(librimel_select_candidate, "NUM &optional SESSION-ID",
          "Select a rime candidate by NUM.\n"
          "When SESSION-ID is provided, use that session.");
static emacs_value librimel_select_candidate(emacs_env *env, ptrdiff_t nargs,
                                             emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;

  int index = env->extract_integer(env, args[0]);
  RimeSessionId session_id = _get_session(rime, env, nargs, args, 1);

  if (!_ensure_given_session(rime, session_id)) {
    em_signal_rimeerr(env, 1, NO_SESSION_ERR);
    return em_nil;
  }

  if (rime->api->select_candidate_on_current_page(session_id, index)) {
    return em_t;
  }
  return em_nil;
}

// output

DOCSTRING(librimel_get_commit, "&optional SESSION-ID",
          "Get rime commit.\n"
          "When SESSION-ID is provided, use that session.");
static emacs_value librimel_get_commit(emacs_env *env, ptrdiff_t nargs,
                                       emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;

  RimeSessionId session_id = _get_session(rime, env, nargs, args, 0);

  if (!_ensure_given_session(rime, session_id)) {
    em_signal_rimeerr(env, 1, NO_SESSION_ERR);
    return em_nil;
  }

  RIME_STRUCT(RimeCommit, commit);
  if (rime->api->get_commit(session_id, &commit)) {
    if (!commit.text) {
      return em_nil;
    }

    char *commit_str = _copy_string(commit.text);
    rime->api->free_commit(&commit);
    // printf("commit str is %s\n", commit_str);

    return env->make_string(env, commit_str, strlen(commit_str));
  }

  return em_nil;
}

DOCSTRING(librimel_get_context, "&optional SESSION-ID",
          "Get rime context.\n"
          "When SESSION-ID is provided, use that session.");
static emacs_value librimel_get_context(emacs_env *env, ptrdiff_t nargs,
                                        emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;

  RimeSessionId session_id = _get_session(rime, env, nargs, args, 0);

  if (!_ensure_given_session(rime, session_id)) {
    em_signal_rimeerr(env, 1, NO_SESSION_ERR);
    return em_nil;
  }

  RIME_STRUCT(RimeContext, context);
  if (!rime->api->get_context(session_id, &context)) {
    em_signal_rimeerr(env, 2, "Cannot get context.");
    return em_nil;
  }

  size_t result_size = 3;
  emacs_value result_array[result_size];

  // 0. context.commit_text_preview
  char *ctp_str = _copy_string(context.commit_text_preview);
  if (ctp_str)
    result_array[0] = CONS_STRING("commit-text-preview", ctp_str);
  else
    result_array[0] = CONS_NIL("commit-text-preview");

  // 2. context.composition
  size_t composition_size = 5;
  emacs_value composition_array[composition_size];
  composition_array[0] = CONS_INT("length", context.composition.length);
  composition_array[1] = CONS_INT("cursor-pos", context.composition.cursor_pos);
  composition_array[2] = CONS_INT("sel-start", context.composition.sel_start);
  composition_array[3] = CONS_INT("sel-end", context.composition.sel_end);

  char *preedit_str = _copy_string(context.composition.preedit);
  if (preedit_str)
    composition_array[4] = CONS_STRING("preedit", preedit_str);
  else
    // When we don't have a preedit,
    // The composition should be nil.
    return em_nil;
  /* composition_array[4] = CONS_NIL("preedit"); */

  emacs_value composition_value =
      em_list(env, composition_size, composition_array);
  result_array[1] = CONS_VALUE("composition", composition_value);

  // 3. context.menu
  if (context.menu.num_candidates) {
    size_t menu_size = 6;
    emacs_value menu_array[menu_size];
    menu_array[0] = CONS_INT("highlighted-candidate-index",
                             context.menu.highlighted_candidate_index);
    menu_array[1] =
        CONS_VALUE("last-page-p", context.menu.is_last_page ? em_t : em_nil);
    menu_array[2] = CONS_INT("num-candidates", context.menu.num_candidates);
    menu_array[3] = CONS_INT("page-no", context.menu.page_no);
    menu_array[4] = CONS_INT("page-size", context.menu.page_size);
    emacs_value carray[context.menu.num_candidates];
    // Build candidates
    for (int i = 0; i < context.menu.num_candidates; i++) {
      RimeCandidate candidate = context.menu.candidates[i];

      emacs_value value = em_string(env, candidate.text);
      if (candidate.comment) {
        emacs_value comment = em_string(env, candidate.comment);
        value = em_propertize(env, value, ":comment", comment);
      }

      carray[i] = value;
    }

    emacs_value candidates = em_list(env, context.menu.num_candidates, carray);
    menu_array[5] = CONS_VALUE("candidates", candidates);
    emacs_value menu = em_list(env, menu_size, menu_array);
    result_array[2] = CONS_VALUE("menu", menu);
  } else {
    result_array[2] = CONS_NIL("menu");
  }

  // build result
  emacs_value result = em_list(env, result_size, result_array);

  rime->api->free_context(&context);

  return result;
}

DOCSTRING(librimel_get_status, "&optional SESSION-ID",
          "Get rime status.\n"
          "When SESSION-ID is provided, use that session.");
static emacs_value librimel_get_status(emacs_env *env, ptrdiff_t nargs,
                                       emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;

  RimeSessionId session_id = _get_session(rime, env, nargs, args, 0);

  if (!_ensure_given_session(rime, session_id)) {
    em_signal_rimeerr(env, 1, NO_SESSION_ERR);
    return em_nil;
  }

  RIME_STRUCT(RimeStatus, status);
  if (!rime->api->get_status(session_id, &status)) {
    em_signal_rimeerr(env, 2, "Cannot get status.");
    return em_nil;
  }

  size_t result_size = 9;
  emacs_value result_array[result_size];

  char *schema_id = _copy_string(status.schema_id);
  if (schema_id)
    result_array[0] = CONS_STRING("schema_id", schema_id);
  else
    result_array[0] = CONS_NIL("schema_id");

  char *schema_name = _copy_string(status.schema_name);
  if (schema_name)
    result_array[1] = CONS_STRING("schema_name", schema_name);
  else
    result_array[1] = CONS_NIL("schema_name");

  result_array[2] =
      CONS_VALUE("is_disabled", status.is_disabled ? em_t : em_nil);
  result_array[3] =
      CONS_VALUE("is_composing", status.is_composing ? em_t : em_nil);
  result_array[4] =
      CONS_VALUE("is_ascii_mode", status.is_ascii_mode ? em_t : em_nil);
  result_array[5] =
      CONS_VALUE("is_full_shape", status.is_full_shape ? em_t : em_nil);
  result_array[6] =
      CONS_VALUE("is_simplified", status.is_simplified ? em_t : em_nil);
  result_array[7] =
      CONS_VALUE("is_traditional", status.is_traditional ? em_t : em_nil);
  result_array[8] =
      CONS_VALUE("is_ascii_punct", status.is_ascii_punct ? em_t : em_nil);

  // build result
  emacs_value result = em_list(env, result_size, result_array);

  rime->api->free_status(&status);

  return result;
}

DOCSTRING(librimel_get_user_config,
          "USER-CONFIG OPTION &optional RETURN-VALUE-TYPE",
          "Get OPTION of rime USER-CONFIG.\n"
          "The return value type can be set with RETURN-VALUE-TYPE.");
static emacs_value librimel_get_user_config(emacs_env *env, ptrdiff_t nargs,
                                            emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;

  if (nargs < 2) {
    em_signal_rimeerr(env, 2, "Invalid arguments.");
    return em_nil;
  }

  const char *config_id = em_get_string(env, args[0]);
  const char *config_key = em_get_string(env, args[1]);
  char *config_type = "cstring";
  if (nargs >= 3 && env->is_not_nil(env, args[2])) {
    config_type = em_get_string(env, args[2]);
  }

  RimeConfig *config = malloc(sizeof(RimeConfig));
  // 注意user_config_open是从user_data_dir下获取
  if (!rime->api->user_config_open(config_id, config)) {
    em_signal_rimeerr(env, 2, "Failed to open user config file.");
    free((char *)config_id);
    free((char *)config_key);
    if (nargs >= 3 && env->is_not_nil(env, args[2])) {
      free(config_type);
    }
    return em_nil;
  }

  bool success = false;
  emacs_value result;
  // printf("get %s for %s\n", config_key, config_type);
  if (strcmp("int", config_type) == 0) {
    int number = 0;
    success = rime->api->config_get_int(config, config_key, &number);
    result = env->make_integer(env, number);
  } else if (strcmp("double", config_type) == 0) {
    double number = 0.0;
    success = rime->api->config_get_double(config, config_key, &number);
    result = env->make_float(env, number);
  } else if (strcmp("bool", config_type) == 0) {
    Bool is_true = false;
    success = rime->api->config_get_bool(config, config_key, &is_true);
    result = is_true ? em_t : em_nil;
  } else {
    const char *string = rime->api->config_get_cstring(config, config_key);
    success = true;
    result = env->make_string(env, string, strnlen(string, CONFIG_MAXSTRLEN));
  }

  rime->api->config_close(config);
  free((char *)config_id);
  free((char *)config_key);
  if (nargs >= 3 && env->is_not_nil(env, args[2])) {
    free(config_type);
  }

  if (!success) {
    em_signal_rimeerr(env, 2, "Failed to get config.");
    return em_nil;
  }

  return result;
}

DOCSTRING(librimel_set_user_config,
          "USER-CONFIG OPTION VALUE &optional VALUE-TYPE",
          "Set rime USER-CONFIG OPTION to VALUE.\n"
          "When VALUE-TYPE is non-nil, VALUE will be converted to this type.");
static emacs_value librimel_set_user_config(emacs_env *env, ptrdiff_t nargs,
                                            emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;

  if (nargs < 3) {
    em_signal_rimeerr(env, 2, "Invalid arguments.");
    return em_nil;
  }

  const char *config_id = em_get_string(env, args[0]);
  const char *config_key = em_get_string(env, args[1]);
  emacs_value value = args[2];
  char *config_type = "string";
  if (nargs >= 4 && env->is_not_nil(env, args[3])) {
    config_type = em_get_string(env, args[3]);
  }

  RimeConfig *config = malloc(sizeof(RimeConfig));
  if (!rime->api->user_config_open(config_id, config)) {
    em_signal_rimeerr(env, 2, "Failed to open user config file.");
    free((char *)config_id);
    free((char *)config_key);
    if (nargs >= 4 && env->is_not_nil(env, args[3])) {
      free(config_type);
    }
    return em_nil;
  }

  if (strcmp("int", config_type) == 0) {
    int number = env->extract_integer(env, value);
    rime->api->config_set_int(config, config_key, number);
  } else if (strcmp("double", config_type) == 0) {
    double number = env->extract_float(env, value);
    rime->api->config_set_double(config, config_key, number);
  } else if (strcmp("bool", config_type) == 0) {
    bool is_true = env->is_not_nil(env, value);
    rime->api->config_set_bool(config, config_key, is_true);
  } else {
    const char *string = em_get_string(env, value);
    rime->api->config_set_string(config, config_key, string);
    free((char *)string);
  }

  rime->api->config_close(config);
  free((char *)config_id);
  free((char *)config_key);
  if (nargs >= 4 && env->is_not_nil(env, args[3])) {
    free(config_type);
  }

  return em_t;
}

DOCSTRING(librimel_get_schema_config,
          "SCHEMA-CONFIG OPTION &optional RETURN-VALUE-TYPE SESSION-ID",
          "Get OPTION of rime SCHEMA-CONFIG.\n"
          "The return value type can be set with RETURN-VALUE-TYPE.\n"
          "When SESSION-ID is provided, use that session.");
static emacs_value librimel_get_schema_config(emacs_env *env, ptrdiff_t nargs,
                                              emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;

  if (nargs < 2) {
    em_signal_rimeerr(env, 2, "Invalid arguments.");
    return em_nil;
  }

  const char *arg0 = em_get_string(env, args[0]);
  const int max_schema_length = 0xff;
  char *schema_id = (char *)malloc(max_schema_length * sizeof(char));
  memset(schema_id, 0, max_schema_length);

  RimeSessionId session_id = _get_session(rime, env, nargs, args, 3);

  if (!_ensure_given_session(rime, session_id)) {
    free(schema_id);
    free((char *)arg0);
    em_signal_rimeerr(env, 1, NO_SESSION_ERR);
    return em_nil;
  }

  if (arg0 == NULL || strlen(arg0) == 0) {
    if (!rime->api->get_current_schema(session_id, schema_id,
                                       max_schema_length)) {
      em_signal_rimeerr(env, 2, "error get current schema");
      free(schema_id);
      free((char *)arg0);
      return em_nil;
    }
  } else {
    if (strlen(arg0) > max_schema_length) {
      em_signal_rimeerr(env, 2, "Schema id too long.");
      free(schema_id);
      free((char *)arg0);
      return em_nil;
    }

    strcpy(schema_id, arg0);
  }

  free((char *)arg0);

  if (strlen(schema_id) == 0) {
    free(schema_id);
    em_signal_rimeerr(env, 2, "Error length of schema id.");
    return em_nil;
  }

  const char *config_key = em_get_string(env, args[1]);
  char *config_type = "cstring";
  if (nargs == 3) {
    config_type = em_get_string(env, args[2]);
  }

  RimeConfig *config = malloc(sizeof(RimeConfig));
  if (!rime->api->schema_open(schema_id, config)) {
    free(schema_id);
    free((char *)config_key);
    if (nargs == 3) {
      free(config_type);
    }
    em_signal_rimeerr(env, 2, "Failed to open schema config file.");
    return em_nil;
  }

  free(schema_id);

  bool success = false;
  emacs_value result;
  // printf("get %s for %s\n", schema_id, config_type);
  if (strcmp("int", config_type) == 0) {
    int number = 0;
    success = rime->api->config_get_int(config, config_key, &number);
    result = env->make_integer(env, number);
  } else if (strcmp("double", config_type) == 0) {
    double number = 0.0;
    success = rime->api->config_get_double(config, config_key, &number);
    result = env->make_float(env, number);
  } else if (strcmp("bool", config_type) == 0) {
    Bool is_true = false;
    success = rime->api->config_get_bool(config, config_key, &is_true);
    result = is_true ? em_t : em_nil;
  } else {
    const char *string = rime->api->config_get_cstring(config, config_key);
    success = true;
    result = env->make_string(env, string, strnlen(string, CONFIG_MAXSTRLEN));
  }

  rime->api->config_close(config);
  free((char *)config_key);
  if (nargs == 3) {
    free(config_type);
  }

  if (!success) {
    em_signal_rimeerr(env, 2, "Failed to get config.");
    return em_nil;
  }

  return result;
}

DOCSTRING(librimel_set_schema_config,
          "SCHEMA-CONFIG OPTION VALUE &optional VALUE-TYPE SESSION-ID",
          "Set rime SCHEMA-CONFIG OPTION to VALUE.\n"
          "When VALUE-TYPE is non-nil, VALUE will be converted to this type.\n"
          "When SESSION-ID is provided, use that session for getting current "
          "schema.");
static emacs_value librimel_set_schema_config(emacs_env *env, ptrdiff_t nargs,
                                              emacs_value args[], void *data) {
  EmacsRime *rime = (EmacsRime *)data;

  if (nargs < 3) {
    em_signal_rimeerr(env, 2, "Invalid arguments.");
    return em_nil;
  }

  const char *arg0 = em_get_string(env, args[0]);
  const int max_schema_length = 0xff;
  char *schema_id = (char *)malloc(max_schema_length * sizeof(char));
  memset(schema_id, 0, max_schema_length);

  RimeSessionId session_id = _get_session(rime, env, nargs, args, 4);

  if (arg0 == NULL || strlen(arg0) == 0) {
    if (!_ensure_given_session(rime, session_id)) {
      free(schema_id);
      free((char *)arg0);
      em_signal_rimeerr(env, 1, NO_SESSION_ERR);
      return em_nil;
    }
    if (!rime->api->get_current_schema(session_id, schema_id,
                                       max_schema_length)) {
      em_signal_rimeerr(env, 2, "Error get current schema.");
      free(schema_id);
      free((char *)arg0);
      return em_nil;
    }
  } else {
    if (strlen(arg0) > max_schema_length) {
      em_signal_rimeerr(env, 2, "Schema id too long.");
      free(schema_id);
      free((char *)arg0);
      return em_nil;
    }

    strcpy(schema_id, arg0);
  }

  free((char *)arg0);

  if (strlen(schema_id) == 0) {
    free(schema_id);
    em_signal_rimeerr(env, 2, "Error length of schema id.");
    return em_nil;
  }

  const char *config_key = em_get_string(env, args[1]);
  emacs_value value = args[2];
  char *config_type = "string";
  if (nargs == 4) {
    config_type = em_get_string(env, args[3]);
  }

  RimeConfig *config = (RimeConfig *)malloc(sizeof(RimeConfig));
  if (!rime->api->schema_open(schema_id, config)) {
    free(schema_id);
    free((char *)config_key);
    if (nargs == 4) {
      free(config_type);
    }
    em_signal_rimeerr(env, 2, "Failed to open schema config file.");
    return em_nil;
  }

  free(schema_id);
  if (strcmp("int", config_type) == 0) {
    int number = env->extract_integer(env, value);
    rime->api->config_set_int(config, config_key, number);
  } else if (strcmp("double", config_type) == 0) {
    double number = env->extract_float(env, value);
    rime->api->config_set_double(config, config_key, number);
  } else if (strcmp("bool", config_type) == 0) {
    bool is_true = env->is_not_nil(env, value);
    rime->api->config_set_bool(config, config_key, is_true);
  } else {
    const char *string = em_get_string(env, value);
    rime->api->config_set_string(config, config_key, string);
    free((char *)string);
  }

  rime->api->config_close(config);
  free((char *)config_key);
  if (nargs == 4) {
    free(config_type);
  }

  return em_t;
}

void librimel_init(emacs_env *env) {
  // Name 'rime' is hardcode in DEFUN micro, so if you edit here,
  // you should edit DEFUN micro too.
  EmacsRime *rime = (EmacsRime *)malloc(sizeof(EmacsRime));

  rime->api = rime_get_api();
  rime->first_run = true; // not used yet

  if (!rime->api) {
    free(rime);
    em_signal_rimeerr(env, 1, "No librime found.");
    return;
  }

  DEFUN("librimel--start", librimel_start, 2, 2);
  DEFUN("librimel-finalize", librimel_finalize, 0, 0);
  DEFUN("librimel-create-session", librimel_create_session, 0, 0);
  DEFUN("librimel-destroy-session", librimel_destroy_session, 1, 1);
  DEFUN("librimel-search", librimel_search, 1, 3);
  DEFUN("librimel-select-schema", librimel_select_schema, 1, 2);
  DEFUN("librimel-get-schema-list", librimel_get_schema_list, 0, 0);

  // input
  DEFUN("librimel-process-key", librimel_process_key, 1, 3);
  DEFUN("librimel-commit-composition", librimel_commit_composition, 0, 1);
  DEFUN("librimel-clear-composition", librimel_clear_composition, 0, 1);
  DEFUN("librimel-select-candidate", librimel_select_candidate, 1, 2);
  DEFUN("librimel-get-input", librimel_get_input, 0, 1);

  // output
  DEFUN("librimel-get-commit", librimel_get_commit, 0, 1);
  DEFUN("librimel-get-context", librimel_get_context, 0, 1);

  // status
  DEFUN("librimel-get-status", librimel_get_status, 0, 1);

  // sync (global operations, no session-id needed)
  DEFUN("librimel-get-sync-dir", librimel_get_sync_dir, 0, 0);
  DEFUN("librimel-sync-user-data", librimel_sync_user_data, 0, 0);

  // user config (global operations, no session-id needed)
  DEFUN("librimel-get-user-config", librimel_get_user_config, 2, 3);
  DEFUN("librimel-set-user-config", librimel_set_user_config, 3, 4);

  // schema config (session-id only used for get_current_schema)
  DEFUN("librimel-get-schema-config", librimel_get_schema_config, 2, 4);
  DEFUN("librimel-set-schema-config", librimel_set_schema_config, 3, 5);
}
