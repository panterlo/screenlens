/**
 * screenlens.h — C header for the ScreenLens core library.
 *
 * Link against libscreenlens_ffi.dylib (macOS) or screenlens_ffi.dll (Windows).
 * All returned char* strings must be freed with sl_free_string().
 */

#ifndef SCREENLENS_H
#define SCREENLENS_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Free a string returned by any sl_* function. */
void sl_free_string(char *s);

/* ---- Config ---- */

/* Load config from default location. Returns JSON string or NULL. */
char *sl_config_load(void);

/* ---- Database ---- */

typedef struct SlDatabase SlDatabase;

/* Open or create database at path. Returns NULL on error. */
SlDatabase *sl_db_open(const char *path);

/* Close and free database handle. */
void sl_db_close(SlDatabase *db);

/* Full-text search. query_json is a JSON SearchQuery. Returns JSON array. */
char *sl_db_search(SlDatabase *db, const char *query_json);

/* List recent screenshots. Returns JSON array. */
char *sl_db_list_recent(SlDatabase *db, uint32_t limit, uint32_t offset);

/* ---- AI Analysis ---- */

/**
 * Analyze a screenshot via the OpenAI-compatible vision API.
 * Blocks until complete. Returns JSON AnalysisResult or NULL.
 */
char *sl_ai_analyze(
    const char *api_url,
    const char *api_key,
    const char *model,
    const uint8_t *image_data,
    size_t image_len
);

#ifdef __cplusplus
}
#endif

#endif /* SCREENLENS_H */
