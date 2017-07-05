#include <libgen.h>
#include <dirent.h>
#include <fcntl.h>
#include <fts.h>
#include <errno.h>
#include <grp.h>
#include <unistd.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <pwd.h>

struct passwd *user_info = NULL;

static struct passwd* get_user_info(const char* user) {
  int string_size = sysconf(_SC_GETPW_R_SIZE_MAX);
  void* buffer = malloc(string_size + sizeof(struct passwd));
  struct passwd *result = NULL;
  if (getpwnam_r(user, buffer, buffer + sizeof(struct passwd), string_size, &result) != 0) {
    free(buffer);
    printf("Can't get user information %s - %s\n", user, strerror(errno));
    return NULL;
  }
  return result;
}

static int change_effective_user(uid_t user, gid_t group) {
  if (geteuid() == user) {
    return 0;
  }
  if (seteuid(0) != 0) {
    printf("Failed to set effective user id 0 - %s\n", strerror(errno));
    return -1;
  }
  if (setegid(group) != 0) {
    printf("Failed to set effective group id %d - %s\n", group, strerror(errno));
    return -1;
  }
  if (seteuid(user) != 0) {
    printf("Failed to set effective user id %d - %s\n", user, strerror(errno));
    return -1;
  }
  return 0;
}

/*
 * @see container-executor.c
 *
 * gcc -o /usr/bin/switch-user switch-user.c
 * chown root:hadoop /usr/bin/switch-user
 * chmod 6050 /usr/bin/switch-user
 * ls -l /usr/bin/switch-user
 * ---Sr-s--- 1 root hadoop 9272 Jul  4 05:35 /usr/bin/switch-user
 * su - yarn -c 'strace /usr/bin/switch-user another_user'
 */
int main(int argc, char **argv) {
    uid_t user = geteuid();
    gid_t group = getegid();
    printf("Current uid= %d, gid= %d\n", user, group);
    setuid(0);
    user = geteuid();
    printf("(should be 0) user= %d\n", user);
    if (argc > 1) {
        user_info = get_user_info(argv[1]);
        printf("Switching to uid= %d, gid= %d\n", user_info->pw_uid, user_info->pw_gid);
        initgroups(argv[1],user_info->pw_gid);
        change_effective_user(user_info->pw_uid, user_info->pw_gid);
        user = geteuid();
        group = getegid();
        printf("Current uid= %d, gid= %d\n", user, group);
        free(user_info);
    }
    return 0;
}