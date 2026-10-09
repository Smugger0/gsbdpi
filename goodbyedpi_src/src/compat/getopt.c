#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "getopt.h"

char *optarg = NULL;
int optind = 1;
int opterr = 1;
int optopt = '?';

static char *nextchar = NULL;

int getopt(int argc, char * const argv[], const char *optstring) {
    return getopt_long(argc, argv, optstring, NULL, NULL);
}

int getopt_long(int argc, char * const argv[], const char *optstring,
                const struct option *longopts, int *longindex) {
    if (optind >= argc || argv[optind] == NULL)
        return -1;

    if (nextchar == NULL || *nextchar == '\0') {
        char *arg = argv[optind];
        if (arg[0] != '-' || arg[1] == '\0')
            return -1;
        if (arg[0] == '-' && arg[1] == '-' && arg[2] == '\0') {
            optind++;
            return -1;
        }

        /* Check long options */
        if (arg[0] == '-' && arg[1] == '-' && longopts != NULL) {
            const char *name = arg + 2;
            const char *eq = strchr(name, '=');
            size_t namelen = eq ? (size_t)(eq - name) : strlen(name);
            int i;

            for (i = 0; longopts[i].name != NULL; i++) {
                if (strncmp(longopts[i].name, name, namelen) == 0 &&
                    strlen(longopts[i].name) == namelen) {
                    if (longindex)
                        *longindex = i;

                    if (longopts[i].has_arg == no_argument) {
                        if (eq) {
                            if (opterr)
                                fprintf(stderr, "%s: option '--%s' doesn't allow an argument\n",
                                        argv[0], longopts[i].name);
                            optopt = longopts[i].val;
                            optind++;
                            return '?';
                        }
                        optarg = NULL;
                    }
                    else if (longopts[i].has_arg == required_argument) {
                        if (eq) {
                            optarg = (char *)(eq + 1);
                        }
                        else if (optind + 1 < argc) {
                            optind++;
                            optarg = argv[optind];
                        }
                        else {
                            if (opterr)
                                fprintf(stderr, "%s: option '--%s' requires an argument\n",
                                        argv[0], longopts[i].name);
                            optopt = longopts[i].val;
                            optind++;
                            return ':';
                        }
                    }
                    else if (longopts[i].has_arg == optional_argument) {
                        if (eq)
                            optarg = (char *)(eq + 1);
                        else
                            optarg = NULL;
                    }

                    optind++;
                    if (longopts[i].flag != NULL) {
                        *longopts[i].flag = longopts[i].val;
                        return 0;
                    }
                    return longopts[i].val;
                }
            }

            if (opterr)
                fprintf(stderr, "%s: unrecognized option '%s'\n", argv[0], arg);
            optopt = 0;
            optind++;
            return '?';
        }

        nextchar = arg + 1;
    }

    /* Short option */
    char c = *nextchar++;
    const char *oli = strchr(optstring, c);

    if (oli == NULL || c == ':') {
        if (opterr)
            fprintf(stderr, "%s: invalid option -- '%c'\n", argv[0], c);
        optopt = c;
        if (*nextchar == '\0')
            optind++;
        return '?';
    }

    if (oli[1] == ':') {
        if (oli[2] == ':') {
            /* Optional argument */
            if (*nextchar != '\0') {
                optarg = nextchar;
                nextchar = NULL;
                optind++;
            }
            else {
                optarg = NULL;
                optind++;
            }
        }
        else {
            /* Required argument */
            if (*nextchar != '\0') {
                optarg = nextchar;
                nextchar = NULL;
                optind++;
            }
            else if (optind + 1 < argc) {
                optind++;
                optarg = argv[optind];
                nextchar = NULL;
                optind++;
            }
            else {
                if (opterr)
                    fprintf(stderr, "%s: option requires an argument -- '%c'\n", argv[0], c);
                optopt = c;
                nextchar = NULL;
                optind++;
                return ':';
            }
        }
    }
    else {
        optarg = NULL;
        if (*nextchar == '\0') {
            nextchar = NULL;
            optind++;
        }
    }

    return c;
}
