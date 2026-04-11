/*
 * test_librimel.c -- Minimal C unit tests for librimel internal helpers.
 *
 * These tests exercise internal C utility functions WITHOUT requiring
 * an Emacs runtime or a running librime instance.  They test pure C
 * logic such as string copying and linked-list management.
 *
 * Build & run:
 *   make test-c
 *
 * Or manually:
 *   gcc -O2 -Wall -I emacs-module/$(emacs --batch --eval '(princ
 * emacs-major-version)') \ -o test/test_librimel test/test_librimel.c -lrime
 *   ./test/test_librimel
 */

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---------------------------------------------------------------------------
 * Re-implement the internal helpers under test (they are static in
 * librimel-core.c, so we copy them here for isolated testing).
 * ---------------------------------------------------------------------------*/

#define CANDIDATE_MAXSTRLEN 1024

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

typedef struct _CandidateLinkedList {
  char *text;
  char *comment;
  struct _CandidateLinkedList *next;
} CandidateLinkedList;

void free_candidate_list(CandidateLinkedList *list) {
  CandidateLinkedList *next = list;
  while (next) {
    CandidateLinkedList *temp = next;
    next = temp->next;
    if (temp->text)
      free(temp->text);
    if (temp->comment)
      free(temp->comment);
    free(temp);
  }
}

/* ---------------------------------------------------------------------------
 * Test infrastructure
 * ---------------------------------------------------------------------------*/

static int tests_run = 0;
static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name)                                                             \
  static void test_##name(void);                                               \
  static void run_test_##name(void) {                                          \
    tests_run++;                                                               \
    printf("  TEST %-50s ", #name);                                            \
    test_##name();                                                             \
    tests_passed++;                                                            \
    printf("PASS\n");                                                          \
  }                                                                            \
  static void test_##name(void)

#define ASSERT(cond)                                                           \
  do {                                                                         \
    if (!(cond)) {                                                             \
      printf("FAIL\n    assertion failed: %s\n    at %s:%d\n", #cond,          \
             __FILE__, __LINE__);                                              \
      tests_failed++;                                                          \
      tests_passed--; /* undo the pre-increment in run_ */                     \
      return;                                                                  \
    }                                                                          \
  } while (0)

#define ASSERT_STR_EQ(a, b)                                                    \
  do {                                                                         \
    if (strcmp((a), (b)) != 0) {                                               \
      printf("FAIL\n    expected \"%s\" == \"%s\"\n    at %s:%d\n", (a), (b),  \
             __FILE__, __LINE__);                                              \
      tests_failed++;                                                          \
      tests_passed--;                                                          \
      return;                                                                  \
    }                                                                          \
  } while (0)

/* ---------------------------------------------------------------------------
 * _copy_string tests
 * ---------------------------------------------------------------------------*/

TEST(copy_string_basic) {
  char *result = _copy_string("hello");
  ASSERT(result != NULL);
  ASSERT_STR_EQ(result, "hello");
  free(result);
}

TEST(copy_string_empty) {
  char *result = _copy_string("");
  ASSERT(result != NULL);
  ASSERT_STR_EQ(result, "");
  free(result);
}

TEST(copy_string_null) {
  char *result = _copy_string(NULL);
  ASSERT(result == NULL);
}

TEST(copy_string_chinese) {
  /* UTF-8 encoded Chinese characters */
  char *result = _copy_string("你好世界");
  ASSERT(result != NULL);
  ASSERT_STR_EQ(result, "你好世界");
  free(result);
}

TEST(copy_string_long) {
  /* Test string near max length */
  char buf[CANDIDATE_MAXSTRLEN + 10];
  memset(buf, 'a', sizeof(buf) - 1);
  buf[sizeof(buf) - 1] = '\0';
  char *result = _copy_string(buf);
  ASSERT(result != NULL);
  /* Should be truncated to CANDIDATE_MAXSTRLEN */
  ASSERT(strlen(result) == CANDIDATE_MAXSTRLEN);
  free(result);
}

TEST(copy_string_is_deep_copy) {
  char original[] = "hello";
  char *result = _copy_string(original);
  ASSERT(result != original); /* different pointer */
  ASSERT_STR_EQ(result, "hello");
  /* Modifying original should not affect copy */
  original[0] = 'X';
  ASSERT_STR_EQ(result, "hello");
  free(result);
}

/* ---------------------------------------------------------------------------
 * CandidateLinkedList tests
 * ---------------------------------------------------------------------------*/

TEST(free_candidate_list_empty) {
  /* Single node with no text */
  CandidateLinkedList *list = malloc(sizeof(CandidateLinkedList));
  list->text = NULL;
  list->comment = NULL;
  list->next = NULL;
  free_candidate_list(list); /* should not crash */
}

TEST(free_candidate_list_single) {
  CandidateLinkedList *list = malloc(sizeof(CandidateLinkedList));
  list->text = _copy_string("hello");
  list->comment = _copy_string("comment");
  list->next = NULL;
  free_candidate_list(list);
}

TEST(free_candidate_list_multiple) {
  CandidateLinkedList *n1 = malloc(sizeof(CandidateLinkedList));
  CandidateLinkedList *n2 = malloc(sizeof(CandidateLinkedList));
  CandidateLinkedList *n3 = malloc(sizeof(CandidateLinkedList));
  n1->text = _copy_string("first");
  n1->comment = NULL;
  n1->next = n2;
  n2->text = _copy_string("second");
  n2->comment = _copy_string("note");
  n2->next = n3;
  n3->text = _copy_string("third");
  n3->comment = NULL;
  n3->next = NULL;
  free_candidate_list(n1);
}

/* ---------------------------------------------------------------------------
 * Main
 * ---------------------------------------------------------------------------*/

int main(void) {
  printf("Running librimel C unit tests...\n\n");

  /* _copy_string tests */
  run_test_copy_string_basic();
  run_test_copy_string_empty();
  run_test_copy_string_null();
  run_test_copy_string_chinese();
  run_test_copy_string_long();
  run_test_copy_string_is_deep_copy();

  /* linked list tests */
  run_test_free_candidate_list_empty();
  run_test_free_candidate_list_single();
  run_test_free_candidate_list_multiple();

  printf("\n%d tests run, %d passed, %d failed.\n", tests_run, tests_passed,
         tests_failed);

  return tests_failed > 0 ? 1 : 0;
}
