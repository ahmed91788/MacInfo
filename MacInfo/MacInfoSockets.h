
#ifndef MACINFO_SOCKETS_H
#define MACINFO_SOCKETS_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    int32_t pid;
    int32_t fd;
    char process_name[256];
    char protocol_name[8];
    char local_address[64];
    uint16_t local_port;
    char remote_address[64];
    uint16_t remote_port;
    char state[32];
} MacInfoConnection;

int macinfo_collect_connections(
    MacInfoConnection *results,
    int capacity
);

#endif
