// Sporkle CLI main entry point

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void print_usage(const char* prog) {
    printf("Usage: %s <command> [options]\n", prog);
    printf("\n");
    printf("Commands:\n");
    printf("  kronos --selftest    Run Kronos runtime self-test (recovery mode: reports runtime path)\n");
    printf("  kronos --info        Show Kronos runtime backend info (recovery mode: reports discovery details)\n");
    printf("  help                 Show this help message\n");
    printf("\n");
}

static int cmd_kronos_selftest(void) {
    fprintf(stderr, "The CLI self-test command is not active in recovery mode.\n");
    fprintf(stderr, "Use library-level runtime initialization and diagnostics for production checks.\n");
    return 2;
}

static int cmd_kronos_info(void) {
    fprintf(stderr, "CLI backend info is not active in recovery mode.\n");
    fprintf(stderr, "Use library-level diagnostics for backend discovery details.\n");
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
