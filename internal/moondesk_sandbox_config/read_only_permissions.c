#include <sys/stat.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

/* Nonmutating counterpart of the existing 0700/0600 setup. */
int moonclaw_private_control_path(const unsigned char *bytes, int length, int directory) {
  if (length < 1 || length > 4096 || memchr(bytes, 0, (size_t)length)) return 0;
  char *path = malloc((size_t)length + 1);
  if (!path) return 0;
  memcpy(path, bytes, (size_t)length); path[length] = 0;
  struct stat value;
  int ok = lstat(path, &value) == 0 && value.st_uid == geteuid() &&
    (directory ? S_ISDIR(value.st_mode) : S_ISREG(value.st_mode)) &&
    (value.st_mode & 0777) == (directory ? 0700 : 0600);
  free(path);
  return ok;
}
