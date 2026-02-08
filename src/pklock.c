/*	PKLOCK.C
 *
 *	locking routines as modified by Petri Kutvonen
 */

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdio.h>
#include <fcntl.h>
#include <string.h>
#include <errno.h>
#include <pwd.h>

#include "estruct.h"
#include "edef.h"
#include "efunc.h"
#include "util.h"

#define MAXLOCK 512
#define MAXNAME 128

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif

#ifndef O_NOFOLLOW
#define O_NOFOLLOW 0
#endif

static char lock_err_path_too_long[] = "LOCK ERROR: lock file path too long";
static char lock_err_not_regular[] = "LOCK ERROR: not a regular file";
static char lock_err_cannot_access[] = "LOCK ERROR: cannot access lock file";
static char lock_err_cannot_write[] = "LOCK ERROR: cannot write lock file";
static char lock_err_cannot_close[] = "LOCK ERROR: cannot close lock file";
static char lock_err_malformed[] = "LOCK ERROR: malformed lock file";
static char lock_err_cannot_remove[] = "LOCK ERROR: cannot remove lock file";

int is_lock_error(const char *msg)
{
	return msg == lock_err_path_too_long
	    || msg == lock_err_not_regular
	    || msg == lock_err_cannot_access
	    || msg == lock_err_cannot_write
	    || msg == lock_err_cannot_close
	    || msg == lock_err_malformed
	    || msg == lock_err_cannot_remove;
}

/**********************
 *
 * if successful, returns NULL  
 * if file locked, returns username of person locking the file
 * if other error, returns "LOCK ERROR: explanation"
 *
 *********************/
char *dolock(char *fname)
{
	int fd;
	static char lname[MAXLOCK], locker[MAXNAME + 1];
	int mask;
	struct stat sbuf;
	ssize_t nread;
	ssize_t nwritten;
	size_t owner_len;

	if (snprintf(lname, sizeof(lname), "%s.lock~", fname)
	    >= (int)sizeof(lname))
		return lock_err_path_too_long;

retry_create:
	mask = umask(0);
	fd = open(lname,
		  O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
		  0666);
	umask(mask);

	/* We created the lock file atomically and now own the lock. */
	if (fd >= 0) {
		if (fstat(fd, &sbuf) != 0) {
			close(fd);
			unlink(lname);
			return lock_err_cannot_access;
		}
		if (!S_ISREG(sbuf.st_mode)) {
			close(fd);
			unlink(lname);
			return lock_err_not_regular;
		}

		/* Generate the owner tag (user@host) for the lock file */
		const char *user = getlogin();
		if (!user) {
			/* No controlling terminal; Try using the passwd entry */
			struct passwd *pw = getpwuid(geteuid());
			if (pw)
				user = pw->pw_name;
		}

		if (!user) {
			/* Still no username; fall back to numeric UID */
			snprintf(locker, sizeof(locker), "uid%d", (int)geteuid());

		} else {
			snprintf(locker, sizeof(locker), "%s", user);
		}
		{
			size_t used = strlen(locker);

			/* Append host safely without overflowing locker. */
			if (used < sizeof(locker) - 1) {
				locker[used++] = '@';
				if (gethostname(locker + used,
						sizeof(locker) - used) != 0)
					locker[used] = '\0';
				locker[sizeof(locker) - 1] = '\0';
			}
		}

		/* Write the owner tag to the lock file */
		owner_len = strlen(locker);
		if (lseek(fd, 0, SEEK_SET) < 0) {
			close(fd);
			unlink(lname);
			return lock_err_cannot_write;
		}
		nwritten = write(fd, locker, owner_len);
		if (nwritten < 0 || (size_t)nwritten != owner_len) {
			close(fd);
			unlink(lname);
			return lock_err_cannot_write;
		}
		if (close(fd) != 0) {
			unlink(lname);
			return lock_err_cannot_close;
		}
		return NULL;
	}

	if (errno == EACCES || errno == EROFS)
		return NULL;

	/* A lock file exists: read and report its owner. */
	if (errno == EEXIST) {
		fd = open(lname, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
		if (fd < 0) {
			if (errno == ENOENT)
				goto retry_create;
			if (errno == EACCES || errno == EROFS)
				return NULL;
			if (errno == ELOOP)
				return lock_err_not_regular;
			return lock_err_cannot_access;
		}

		if (fstat(fd, &sbuf) != 0) {
			close(fd);
			return lock_err_cannot_access;
		}
		if (!S_ISREG(sbuf.st_mode)) {
			close(fd);
			return lock_err_not_regular;
		}

		nread = read(fd, locker, MAXNAME);
		if (close(fd) != 0 && nread >= 0)
			return lock_err_cannot_access;
		if (nread < 0)
			return lock_err_cannot_access;
		if (nread == 0)
			return lock_err_malformed;

		locker[nread > MAXNAME ? MAXNAME : nread] = '\0';
		return locker;
	}

	if (errno == ELOOP)
		return lock_err_not_regular;
	return lock_err_cannot_access;
}

/*********************
 *
 * undolock -- unlock the file fname
 *
 * if successful, returns NULL
 * if other error, returns "LOCK ERROR: explanation"
 *
 *********************/

char *undolock(char *fname)
{
	static char lname[MAXLOCK];

	if (snprintf(lname, sizeof(lname), "%s.lock~", fname)
	    >= (int)sizeof(lname))
		return lock_err_path_too_long;
	if (unlink(lname) != 0) {
		if (errno == EACCES || errno == ENOENT)
			return NULL;
		if (errno == EROFS)
			return NULL;
		return lock_err_cannot_remove;
	}
	return NULL;
}
