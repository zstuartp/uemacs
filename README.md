# uEmacs/PK 4.0

A fork of uEmacs with a focus on improving portability and stability.

## Build

```sh
make
./build/bin/em
```

## Install

```sh
make
make install
```

Install to a user prefix (no root):

```sh
make install PREFIX="$HOME/.local"
```

## Status

| Platform | `master` | `testing` |
|---|---|---|
| Linux | ![Linux master][m-linux] | ![Linux testing][t-linux] |
| macOS | ![macOS master][m-macos] | ![macOS testing][t-macos] |
| FreeBSD | ![FreeBSD master][m-freebsd] | ![FreeBSD testing][t-freebsd] |
| Cygwin/Windows | ![Windows master][m-win] | ![Windows testing][t-win] |

[m-linux]: https://img.shields.io/github/check-runs/zstuartp/uemacs/master?nameFilter=Linux&label=Linux&logo=github&style=flat-square
[t-linux]: https://img.shields.io/github/check-runs/zstuartp/uemacs/testing?nameFilter=Linux&label=Linux&logo=github&style=flat-square
[m-macos]: https://img.shields.io/github/check-runs/zstuartp/uemacs/master?nameFilter=macOS&label=macOS&logo=github&style=flat-square
[t-macos]: https://img.shields.io/github/check-runs/zstuartp/uemacs/testing?nameFilter=macOS&label=macOS&logo=github&style=flat-square
[m-freebsd]: https://img.shields.io/github/check-runs/zstuartp/uemacs/master?nameFilter=FreeBSD%20%28VM%29&label=FreeBSD&logo=github&style=flat-square
[t-freebsd]: https://img.shields.io/github/check-runs/zstuartp/uemacs/testing?nameFilter=FreeBSD%20%28VM%29&label=FreeBSD&logo=github&style=flat-square
[m-win]: https://img.shields.io/github/check-runs/zstuartp/uemacs/master?nameFilter=Windows%20%28Cygwin%20POSIX%29&label=Cygwin%2FWindows&logo=github&style=flat-square
[t-win]: https://img.shields.io/github/check-runs/zstuartp/uemacs/testing?nameFilter=Windows%20%28Cygwin%20POSIX%29&label=Cygwin%2FWindows&logo=github&style=flat-square
