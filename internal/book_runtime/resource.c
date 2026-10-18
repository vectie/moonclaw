#include <moonbit.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* No cwd or filesystem mutation. -1 means absent; -2 means denied/error. */
static int32_t open_path(const unsigned char *raw, int32_t length, int storage, int create) {
  if (length < 2 || length > 4096 || raw[0] != '/' || raw[length-1] == '/' || memchr(raw,0,(size_t)length)) return -2;
  char *path = malloc((size_t)length + 1);
  if (!path) return -2;
  memcpy(path,raw,(size_t)length); path[length] = 0;
  int fd = open("/",O_RDONLY|O_DIRECTORY|O_CLOEXEC|O_NOFOLLOW);
  if (fd < 0) { free(path); return -2; }
  char *part = path + 1;
  for (;;) {
    char *slash = strchr(part,'/');
    if (slash) *slash = 0;
    if (!*part || !strcmp(part,".") || !strcmp(part,"..")) { close(fd); free(path); return -2; }
    int flags = O_RDONLY|O_CLOEXEC|O_NOFOLLOW|O_NONBLOCK;
    if (slash) flags |= O_DIRECTORY;
    else if (storage) flags = O_RDWR|O_CLOEXEC|O_NOFOLLOW|O_NONBLOCK|(create ? (O_CREAT|O_EXCL) : 0);
    if (slash && create) {
      if (mkdirat(fd,part,0755)) { if (errno != EEXIST) { close(fd); free(path); return -2; } }
      else if (fsync(fd)) { close(fd); free(path); return -2; }
    }
    int next = openat(fd,part,flags,0644);
    int created_file = next >= 0 && !slash && storage && create;
    if (next < 0 && errno == EEXIST && !slash && storage && create)
      next = openat(fd,part,flags & ~(O_CREAT|O_EXCL),0644);
    int saved = errno;
    if (created_file && fsync(fd)) { close(next); close(fd); free(path); return -2; }
    close(fd);
    if (next < 0) { free(path); return saved == ENOENT ? -1 : -2; }
    fd = next;
    if (!slash) break;
    part = slash + 1;
  }
  free(path);
  struct stat value;
  if (fstat(fd,&value) || !S_ISREG(value.st_mode)) { close(fd); return -2; }
  return fd;
}

MOONBIT_FFI_EXPORT int32_t moonclaw_book_resource_open(const unsigned char *raw, int32_t length) { return open_path(raw,length,0,0); }
MOONBIT_FFI_EXPORT int32_t moonclaw_book_storage_open(const unsigned char *raw, int32_t length, int32_t create) { return open_path(raw,length,1,create); }
MOONBIT_FFI_EXPORT int32_t moonclaw_book_same_file(int32_t left, int32_t right) {
  struct stat a,b;
  return fstat(left,&a)==0 && fstat(right,&b)==0 && a.st_dev==b.st_dev && a.st_ino==b.st_ino && S_ISREG(a.st_mode) && S_ISREG(b.st_mode);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t moonclaw_book_resource_read(int32_t fd, int32_t *status) {
  const size_t limit = 16u * 1024u * 1024u;
  *status = -1;
  struct stat before, after;
  if (fstat(fd,&before) || !S_ISREG(before.st_mode) || before.st_size < 0 || (uint64_t)before.st_size > limit)
    return moonbit_make_bytes(0,0);
  size_t size = (size_t)before.st_size, used = 0;
  unsigned char *buffer = malloc(size + 1);
  if (!buffer) return moonbit_make_bytes(0,0);
  while (used < size + 1) {
    ssize_t count = read(fd,buffer + used,size + 1 - used);
    if (count < 0 && errno == EINTR) continue;
    if (count < 0) { free(buffer); return moonbit_make_bytes(0,0); }
    if (!count) break;
    used += (size_t)count;
  }
  if (used != size || fstat(fd,&after) || before.st_size != after.st_size || before.st_ino != after.st_ino || before.st_dev != after.st_dev) {
    free(buffer); return moonbit_make_bytes(0,0);
  }
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)used,0);
  if (used) memcpy(result,buffer,used);
  free(buffer);
  *status = 0;
  return result;
}

MOONBIT_FFI_EXPORT void moonclaw_book_resource_close(int32_t fd) { if (fd >= 0) close(fd); }
