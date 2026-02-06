/*	posix.c
 *
 *      The functions in this file negotiate with the operating system for
 *      characters, and write characters in a barely buffered fashion on the
 *      display. All operating systems.
 *
 *	modified by Petri Kutvonen
 *
 *	based on termio.c, with all the old cruft removed, and
 *	fixed for termios rather than the old termio.. Linus Torvalds
 */

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>
#include <sys/ioctl.h>

#if defined(__CYGWIN__)
#  include <sys/socket.h>
#endif

#include "estruct.h"
#include "edef.h"
#include "efunc.h"
#include "utf8.h"

/*
 *  The following are gaurds to ensure these various POSIX flags are defined.
 *
 *  Not all systems define these flags as many of them are considered optional
 *  by the standard (e.g. OLCUC and XCASE on macOS).
 */
#ifndef OLCUC
#define OLCUC 0		/* OLCUC is not defined on macOS	*/
#endif
#ifndef XCASE
#define XCASE 0		/* XCASE is not define on macOS		*/
#endif
#ifndef ECHOCTL
#define ECHOCTL 0
#endif
#ifndef ECHOPRT
#define ECHOPRT 0
#endif
#ifndef ECHOKE
#define ECHOKE 0
#endif
#ifndef FLUSHO
#define FLUSHO 0
#endif
#ifndef PENDIN
#define PENDIN 0
#endif
#ifndef IEXTEN
#define IEXTEN 0
#endif

/* Not defined on FreeBSD */
#ifndef ONLCR
#define ONLCR 0
#endif
#ifndef OCRNL
#define OCRNL 0
#endif
#ifndef ONOCR
#define ONOCR 0
#endif
#ifndef ONLRET
#define ONLRET 0
#endif

#ifndef HAVE_SETBUFFER
/* Prefer standard C setvbuf() when setbuffer() isn't available */
#define setbuffer(stream, buf, size) (void)setvbuf((stream), (buf), _IOFBF, (size))
#endif

static int kbdflgs;				/* saved keyboard fd flags      */
static int kbdpoll;				/* in O_NDELAY mode             */

static struct termios otermios;			/* original terminal characteristics */
static struct termios ntermios;			/* charactoristics to use inside */

#define TBUFSIZ 128
static char tobuf[TBUFSIZ];			/* terminal output buffer */

/*
 * This function is called once to set up the terminal device streams.
 * On VMS, it translates TT until it finds the terminal, then assigns
 * a channel to it and sets it raw. On CPM it is a no-op.
 */
void ttopen(void)
{
	tcgetattr(0, &otermios);		/* save old settings */

	/*
	 * base new settings on old ones - don't change things
	 * we don't know about
	 */
	ntermios = otermios;

	/* raw CR/NL etc input handling, but keep ISTRIP if we're on a 7-bit line */
	ntermios.c_iflag &= ~(IGNBRK | BRKINT | IGNPAR | PARMRK | INPCK | INLCR | IGNCR | ICRNL);

	/* raw CR/NR etc output handling */
	ntermios.c_oflag &= ~(OPOST | ONLCR | OLCUC | OCRNL | ONOCR | ONLRET);

	/* No signal handling, no echo etc */
	ntermios.c_lflag &= ~(ISIG | ICANON | XCASE | ECHO | ECHOE | ECHOK
			      | ECHONL | NOFLSH | TOSTOP | ECHOCTL |
			      ECHOPRT | ECHOKE | FLUSHO | PENDIN | IEXTEN);

	/* one character, no timeout */
	ntermios.c_cc[VMIN] = 1;
	ntermios.c_cc[VTIME] = 0;
	tcsetattr(0, TCSADRAIN, &ntermios);	/* and activate them */

	/*
	 * provide a smaller terminal output buffer so that
	 * the type ahead detection works better (more often)
	 */
	setbuffer(stdout, &tobuf[0], TBUFSIZ);

	kbdflgs = fcntl(0, F_GETFL, 0);
	kbdpoll = FALSE;

	/* on all screens we are not sure of the initial position
	   of the cursor                                        */
	ttrow = 999;
	ttcol = 999;
}

/*
 * This function gets called just before we go back home to the command
 * interpreter. On VMS it puts the terminal back in a reasonable state.
 * Another no-operation on CPM.
 */
void ttclose(void)
{
	tcsetattr(0, TCSADRAIN, &otermios);	/* restore terminal settings */
}

/*
 * Write a character to the display. On VMS, terminal output is buffered, and
 * we just put the characters in the big array, after checking for overflow.
 * On CPM terminal I/O unbuffered, so we just write the byte out. Ditto on
 * MS-DOS (use the very very raw console output routine).
 */
int ttputc(int c)
{
	char utf8[6];
	int bytes;

	bytes = unicode_to_utf8(c, utf8);
	fwrite(utf8, 1, bytes, stdout);
	return 0;
}

/*
 * Flush terminal buffer. Does real work where the terminal output is buffered
 * up. A no-operation on systems where byte at a time terminal I/O is done.
 */
void ttflush(void)
{
/*
 * Add some terminal output success checking, sometimes an orphaned
 * process may be left looping on SunOS 4.1.
 *
 * How to recover here, or is it best just to exit and lose
 * everything?
 *
 * jph, 8-Oct-1993
 * Jani Jaakkola suggested using select after EAGAIN but let's just wait a bit
 *
 */
	int status;

	status = fflush(stdout);
	while (status < 0 && errno == EAGAIN) {
		sleep(1);
		status = fflush(stdout);
	}
	if (status < 0)
		exit(15);
}

/*
 * Small tty input buffer
 */
static struct {
	int nr;
	char buf[32];
} TT;

/* Pause for x*.1 second lag or until keypress */
static void pause_read(int pause)
{
	size_t avail;
	ssize_t n;

	n = 0;

	ntermios.c_cc[VMIN] = 0;
	ntermios.c_cc[VTIME] = pause;
	tcsetattr(0, TCSANOW, &ntermios);

	/* Clamp to avoid size_t underflow and potential over-read */
	if (TT.nr < 0)
		TT.nr = 0;
	avail = sizeof(TT.buf);
	if ((size_t)TT.nr >= avail)
		goto out;
	avail -= (size_t)TT.nr;

	n = read(0, TT.buf + TT.nr, avail);

out:

	/* Undo timeout */
	ntermios.c_cc[VMIN] = 1;
	ntermios.c_cc[VTIME] = 0;
	tcsetattr(0, TCSANOW, &ntermios);

	if (n > 0)
		TT.nr += (int)n;
}

void ttpause(void)
{
	if (term.t_pause && !TT.nr)
		pause_read(term.t_pause);
}

/*
 * Read a character from the terminal, performing no editing and doing no echo
 * at all. More complex in VMS that almost anyplace else, which figures. Very
 * simple on CPM, because the system can do exactly what you want.
 */
int ttgetc(void)
{
	unicode_t c;
	int count, bytes = 1, expected;

	count = TT.nr;
	if (!count) {
		ssize_t nread;

		nread = read(0, TT.buf, sizeof(TT.buf));
		if (nread <= 0)
			return 0;
		if (nread > (ssize_t)sizeof(TT.buf))
			nread = (ssize_t)sizeof(TT.buf);
		TT.nr = (int)nread;
		count = TT.nr;
	}

	c = (unsigned char)TT.buf[0];
	if (c != 27 && c < 128)
		goto done;

	/*
	 * Lazy. We don't bother calculating the exact
	 * expected length. We want at least two characters
	 * for the special character case (ESC+[) and for
	 * the normal short UTF8 sequence that starts with
	 * the 110xxxxx pattern.
	 *
	 * But if we have any of the other patterns, just
	 * try to get more characters. At worst, that will
	 * just result in a barely perceptible 0.1 second
	 * delay for some *very* unusual utf8 character
	 * input.
	 */
	expected = 2;
	if ((c & 0xe0) == 0xe0)
		expected = 6;

	/* Special character - try to re-fill the buffer */
	if (count < expected)
		pause_read(1);

	if (TT.nr > 1) {
		unsigned char second = TT.buf[1];

		/* Turn ESC+'[' into CSI */
		if (c == 27 && second == '[') {
			bytes = 2;
			c = 128 + 27;
			goto done;
		}
	}
	bytes = utf8_to_unicode(TT.buf, 0, TT.nr, &c);

	/* Hackety hack! Turn no-break space into regular space */
	if (c == 0xa0)
		c = ' ';
 done:
	TT.nr -= bytes;
	if (TT.nr < 0)
		TT.nr = 0;
	memmove(TT.buf, TT.buf + bytes, (size_t)TT.nr);
	return c;
}

/* typahead:	Check to see if any characters are already in the
		keyboard TT.buf
*/

int typahead(void)
{
	int x;

	if (ioctl(0, FIONREAD, &x) < 0)
		x = 0;
	return x + TT.nr;
}
