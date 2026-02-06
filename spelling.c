/*
 * 	A small wrapper around Hunspell,
 *	providing spelling support for those in nead.
 *
 *	Added by Zackary Parsons.
 */

#include "spelling.h"

#include <hunspell.h>

#include <errno.h>
#include <locale.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const size_t MAX_PATH_LENGTH = 1024;

static Hunhandle *hunspell_handle = NULL;

static bool file_accessable(const char *path) {
	if (path == NULL || path[0] == '\0')
		return false;

	return (access(path, R_OK) == 0);
}

/*
 * Parse the locale string into a tag to pass to hunspell
 * (e.g. "en_US.UTF-8" -> "en_US")
 */
static void parse_locale_to_tag(char *out, size_t out_size, const char *in) {
	size_t i = 0;
	size_t j = 0;
	
	/* Nothing to do */
	if (out == NULL || out == 0 || in == NULL || *in == '\0')
		return;

	for (i = 0; in[i] != '\0'; ++i) {
		char ch = '\0';

		if (in[i] == '.' || in[i] == '@')
			break;
		if (j + 1 > out_size)
			break;

		ch = in[i];
		if (ch == '-')
			ch = '_';

		out[j++] = ch;
	}
	out[j] = '\0';

	/* Treat C/POSIX locales as "" for hunspell */
	if (strcmp(out, "C") == 0 || strcmp(out, "POSIX") == 0)
		out[0] = '\0';
}

static void language_from_tag(char *lang_out, size_t out_size, const char *tag) {
	size_t i = 0;

	if (lang_out == NULL || out_size == 0 || tag == NULL || *tag == '\0')
		return;

	while ((tag[i] != '\0') && (tag[i] != '_') && (i + 1 < out_size)) {
		lang_out[i] = tag[i];
		++i;
	}
	lang_out[i] = '\0';
}

static Hunhandle *hunspell_init(const char *tag, const char *language) {
	Hunhandle *hs_handle_return = NULL;
	char aff_path[MAX_PATH_LENGTH];
	char dic_path[MAX_PATH_LENGTH];
	char current_dic_dir[MAX_PATH_LENGTH];
	const char *dic_paths = NULL;
	size_t i = 0;
	size_t j = 0;

	if (tag == NULL
	    || tag[0] == '\0'
	    || language == NULL
	    || language[0] == '\0') {
		perror("uemacs: Attempted to initialize Hunspell without specifying a dictionary/language");
		return NULL;
	}

	/* Get the list of colon-separated paths from DICPATH in the sys env
	 * TODO: Append additional directories to search.
	 * */
	dic_paths = getenv("DICPATH");
	if (dic_paths == NULL || dic_paths[0] == '\0') {
		perror("uemacs: DICPATH is not set in your evnironment.");
		return NULL;
	}

	/*
	 * Keep searching until we find readable {tag}.aff and {tag}.dic files.
	 * Only once accessable files are found do we attempt to call
	 * Hunspell_create(). Until then the handle will remain NULL.
	 */
	while (hs_handle_return == NULL) {
		char ch = '\0';

		if (j > sizeof(current_dic_dir) - 1)
			break;

		ch = dic_paths[i + j];
		if (ch == '\0' || ch == ':') {
			current_dic_dir[j] = '\0';
			snprintf(aff_path, sizeof(aff_path), "%s/%s.aff",
				 current_dic_dir, tag);
			snprintf(dic_path, sizeof(dic_path), "%s/%s.dic",
				 current_dic_dir, tag);

			if (ch == '\0') /* End of directory list */
				break;
			current_dic_dir[j] = '\0';
			i = j;
			j = 0;

			if (file_accessable(aff_path) == false
			    || file_accessable(dic_path) == false)
				continue;

			hs_handle_return = Hunspell_create(aff_path, dic_path);
		}

		++j;
	}

	return hs_handle_return;
}

static void load_local_dictionary(const char *dic_path) {
	struct stat st;
	
	if (hunspell_handle == NULL || dic_path == NULL)
		return;

	if (!stat(dic_path, &st) && S_ISREG(st.st_mode))
		Hunspell_add_dic(hunspell_handle, dic_path);
}

int spellcheck(const char *word) {
	if (hunspell_handle == NULL)
		return 1;
	return Hunspell_spell(hunspell_handle, word);
}

int spelling_init(void) {
	static const size_t MAX_TAG_LENGTH = 64;

	char tag[MAX_TAG_LENGTH];
	char language[MAX_TAG_LENGTH];
	const char *dictionary = NULL;

	/* Oops! We already inited... */
	if (hunspell_handle != NULL) {
		perror("UEmacs Warning: Attempted to initialize hunspell twice.");
		return 1;
	}

	/* POSIX: "" means use user locale from LC_ALL -> LC_* -> LANG */
	(void)setlocale(LC_ALL, "");

	/* Get the user's dictionary/locale tag */
	dictionary = getenv("DICTIONARY");
	if (dictionary && *dictionary != '\0') {
		parse_locale_to_tag(tag, sizeof(tag), dictionary);
	} else {
		parse_locale_to_tag(tag, sizeof(tag), setlocale(LC_CTYPE, NULL));
	}

	if (tag[0] == '\0') {
		/* No usable tag; make it cheeseburger instead */
		strncpy(tag, "en_US", sizeof(tag));
		tag[sizeof(tag) - 1] = '\0'; /* ensure last char is NULL */
	}

	/* Get the language */
	language_from_tag(language, sizeof(language), tag);

	hunspell_handle = hunspell_init(tag, language);

	if (hunspell_handle == NULL) {
		perror("uemaces: Failed to initialize hunspell for spelling support.");
		return 1;
	} else {
		const char *home = getenv("HOME");
		char home_dic_path[MAX_PATH_LENGTH];

		load_local_dictionary(".dictionary");

		if (home != NULL) {
			snprintf(home_dic_path, sizeof(home_dic_path), "%s/.dictionary", home);
			load_local_dictionary(home_dic_path);
		}
	}

	return 0;
}

void spelling_shutdown(void) {
	if (hunspell_handle == NULL)
		return;

	Hunspell_destroy(hunspell_handle);
	hunspell_handle = NULL;
}
