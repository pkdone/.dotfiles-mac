/* Interpose stat/lstat so /Applications/Tailscale.app can be present or
 * absent without touching the host filesystem.
 *
 * TAILSCALE_APP_VIEW=installed  the bundle stats as a directory
 * TAILSCALE_APP_VIEW=absent     the bundle stats as missing (ENOENT)
 *
 * Not TAILSCALE_VIEW: tests/run-all.sh assigns that name to "" at startup,
 * and the empty value stays exported into the test workers.
 *
 * Only those paths are changed. [ -d ] uses stat. [ -x ] uses access, which
 * is left alone, so a missing binary is not executed.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

static const char prefix[] = "/Applications/Tailscale.app";

static int under_app(const char *path) {
  size_t n;
  if (path == NULL) {
    return 0;
  }
  n = sizeof(prefix) - 1;
  if (strncmp(path, prefix, n) != 0) {
    return 0;
  }
  return path[n] == '\0' || path[n] == '/';
}

/* 1: filled st, -1: error already in errno, 0: caller should use the real call. */
static int fake_stat(const char *path, struct stat *st) {
  const char *view = getenv("TAILSCALE_APP_VIEW");
  if (!under_app(path) || view == NULL) {
    return 0;
  }
  if (strcmp(view, "absent") == 0) {
    errno = ENOENT;
    return -1;
  }
  if (strcmp(view, "installed") != 0) {
    return 0;
  }
  memset(st, 0, sizeof(*st));
  st->st_mode = S_IFDIR | 0755;
  st->st_nlink = 2;
  st->st_uid = getuid();
  st->st_gid = getgid();
  return 1;
}

static int (*real_stat)(const char *, struct stat *);
static int (*real_lstat)(const char *, struct stat *);
static int in_init;

/* dlsym can call stat while we are still resolving it. The kernel call is
 * only used for that window; afterwards glibc fills struct stat. */
static int kernel_stat(const char *path, struct stat *st, int flags) {
  return (int)syscall(SYS_newfstatat, AT_FDCWD, path, st, flags);
}

static void load_real(void) {
  if (real_stat != NULL && real_lstat != NULL) {
    return;
  }
  if (in_init) {
    return;
  }
  in_init = 1;
  real_stat = dlsym(RTLD_NEXT, "stat");
  real_lstat = dlsym(RTLD_NEXT, "lstat");
  in_init = 0;
}

int stat(const char *path, struct stat *st) {
  int kind;
  load_real();
  kind = fake_stat(path, st);
  if (kind == 1) {
    return 0;
  }
  if (kind < 0) {
    return -1;
  }
  if (real_stat == NULL) {
    return kernel_stat(path, st, 0);
  }
  return real_stat(path, st);
}

int lstat(const char *path, struct stat *st) {
  int kind;
  load_real();
  kind = fake_stat(path, st);
  if (kind == 1) {
    return 0;
  }
  if (kind < 0) {
    return -1;
  }
  if (real_lstat == NULL) {
    return kernel_stat(path, st, AT_SYMLINK_NOFOLLOW);
  }
  return real_lstat(path, st);
}
