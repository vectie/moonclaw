#include "moonbit.h"
#include <errno.h>
#include <stdio.h>

MOONBIT_FFI_EXPORT
int32_t
moonbit_moonclaw_fs_rename(
  moonbit_bytes_t source,
  moonbit_bytes_t destination
) {
  errno = 0;
  if (rename((const char *)source, (const char *)destination) == 0) {
    return 0;
  }
  return errno;
}
