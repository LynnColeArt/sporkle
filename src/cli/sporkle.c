// Sporkle CLI main entry point

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void print_usage(const char* prog) {
    printf("Usage: %s <command> [options]\n", prog);
    printf("\n");
    printf("Commands:\n");
    printf("  kronos --selftest    Run Kronos runtime self-test (placeholder)\n");
    printf("  kronos --info        Show Kronos runtime backend info (placeholder)\n");
    printf("  help                 Show this help message\n");
    printf("\n");
}

static int cmd_kronos_selftest(void) {
    fprintf(stdout, "Kronos self-test placeholder for CLI pass.\n");
    fprintf(stdout, "Use library-level runtime initialization paths for production checks.\n");
    return 2;
}

static int cmd_kronos_info(void) {
    fprintf(stdout, "Kronos info placeholder for CLI pass.\n");
    fprintf(stdout, "Runtime discovery/reporting is available through library APIs and logs.\n");
    return 2;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    if (strcmp(argv[1], "kronos") == 0 && argc >= 3) {
        if (strcmp(argv[2], "--selftest") == 0) {
            return cmd_kronos_selftest();
        }
        if (strcmp(argv[2], "--info") == 0) {
            return cmd_kronos_info();
        }
    } else if (strcmp(argv[1], "help") == 0) {
        print_usage(argv[0]);
        return 0;
    }

    fprintf(stderr, "Unknown command: %s\n", argv[1]);
    print_usage(argv[0]);
    return 1;
}
