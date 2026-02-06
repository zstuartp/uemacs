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

/**********************
 *
 * if successful, returns NULL  
 * if file locked, returns username of person locking the file
 * if other error, returns "LOCK ERROR: explanation"
 *
 *********************/
char *dolock(char *fname)
{
	int fd, n;
	static char lname[MAXLOCK], locker[MAXNAME + 1];
	int mask;
	struct stat sbuf;

	strcat(strcpy(lname, fname), ".lock~");

	/* check that we are not being cheated, qname must point to     */
	/* a regular file - even this code leaves a small window of     */
	/* vulnerability but it is rather hard to exploit it            */

	if (lstat(lname, &sbuf) == 0)
		if (!S_ISREG(sbuf.st_mode))
			return "LOCK ERROR: not a regular file";

	mask = umask(0);
	fd = open(lname, O_RDWR | O_CREAT, 0666);
	umask(mask);
	if (fd < 0) {
		if (errno == EACCES)
			return NULL;
		if (errno == EROFS)
			return NULL;
		return "LOCK ERROR: cannot access lock file";
	}
	if ((n = read(fd, locker, MAXNAME)) < 1) {
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
		strcat(locker + strlen(locker), "@");
		gethostname(locker + strlen(locker), 64);

		/* Write the owner tag to the lock file */
		lseek(fd, 0, SEEK_SET);
		if (write(fd, locker, strlen(locker)))
			perror("uemacs: ERROR: failed to write to lock file.");
		close(fd);
		return NULL;
	}
	locker[n > MAXNAME ? MAXNAME : n] = 0;
	return locker;
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

	strcat(strcpy(lname, fname), ".lock~");
	if (unlink(lname) != 0) {
		if (errno == EACCES || errno == ENOENT)
			return NULL;
		if (errno == EROFS)
			return NULL;
		return "LOCK ERROR: cannot remove lock file";
	}
	return NULL;
}
