/* -*- mode: c; indent-tabs-mode: nil; c-basic-offset: 4; coding: utf-8-unix -*- */
/* copy of https://gist.github.com/shinaisan/4050281 */
#include <stdio.h>
#include <stdint.h>
#include <sys/resource.h>

void print_rlimit(struct rlimit *r, const char *name) {
    int64_t cur;                /* Soft limit */
    int64_t max;                /* Hard limit */
    cur = r->rlim_cur;
    max = r->rlim_max;
    printf("RLIMIT_%s :rlim_cur => %#llx, :rlim_max => %#llx¥n",
           name, cur, max);
}

int main(int argc, char *argv[]) {
    struct rlimit rlim;
    int resources[] = {RLIMIT_CORE, RLIMIT_CPU, RLIMIT_DATA, RLIMIT_FSIZE,
                       RLIMIT_MEMLOCK, RLIMIT_NOFILE, RLIMIT_NPROC, RLIMIT_RSS,
                       RLIMIT_STACK};
    const char *names[] = {"CORE", "CPU", "DATA", "FSIZE",
                           "MEMLOCK", "NOFILE", "NPROC", "RSS",
                           "STACK"};
    int n = sizeof(resources)/sizeof(resources[0]);
    int i;
    for (i = 0; i < n; i++) {
        getrlimit(resources[i], &rlim);
        print_rlimit(&rlim, names[i]);
    }

    /*struct rlimit rlp;
    if (getrlimit(RLIMIT_NOFILE, &rlp) == -1) {
        throw_internal_error(env, "getrlimit failed");
        return -1;
    }
    return (jlong) rlp.rlim_cur; */
    return 0;
}