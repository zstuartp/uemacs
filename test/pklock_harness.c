#include <stdio.h>
#include <string.h>

const char *dolock(char *fname);
const char *undolock(char *fname);
int is_lock_error(const char *msg);

static int lock_status(const char *msg)
{
	if (is_lock_error(msg))
		return 3;
	return 2;
}

int main(int argc, char **argv)
{
	const char *msg;

	if (argc != 3) {
		fprintf(stderr, "usage: %s <lock|unlock> <path>\n", argv[0]);
		return 64;
	}

	if (strcmp(argv[1], "lock") == 0) {
		msg = dolock(argv[2]);
		if (msg == NULL) {
			puts("OK");
			return 0;
		}
		puts(msg);
		return lock_status(msg);
	}

	if (strcmp(argv[1], "unlock") == 0) {
		msg = undolock(argv[2]);
		if (msg == NULL) {
			puts("OK");
			return 0;
		}
		puts(msg);
		return lock_status(msg);
	}

	fprintf(stderr, "unknown action: %s\n", argv[1]);
	return 64;
}
