/* -*- mode: c; indent-tabs-mode: nil; c-basic-offset: 4; coding: utf-8-unix -*- */
/* @see: https://gist.github.com/shinaisan/4050281 */
#include <stdio.h>
#include <stdint.h>
#include <sys/resource.h>

int main(int argc, char *argv[]) {
    struct rlimit rlp;
    getrlimit(RLIMIT_NOFILE, &rlp);
    printf("%ld", rlp.rlim_cur);    //rlim_max for hard limit
    return 0;
}
