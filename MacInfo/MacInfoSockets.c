
#include "MacInfoSockets.h"

#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static const char *tcp_state_name(int state) {
    switch (state) {
        case 0: return "CLOSED";
        case 1: return "LISTEN";
        case 2: return "SYN_SENT";
        case 3: return "SYN_RECEIVED";
        case 4: return "ESTABLISHED";
        case 5: return "CLOSE_WAIT";
        case 6: return "FIN_WAIT_1";
        case 7: return "CLOSING";
        case 8: return "LAST_ACK";
        case 9: return "FIN_WAIT_2";
        case 10: return "TIME_WAIT";
        default: return "UNKNOWN";
    }
}

int macinfo_collect_connections(
    MacInfoConnection *results,
    int capacity
) {
    if (!results || capacity <= 0) return 0;

    int pidCapacity = proc_listallpids(NULL, 0);
    if (pidCapacity <= 0) return 0;

    pidCapacity += 256;

    pid_t *pids = calloc(pidCapacity, sizeof(pid_t));
    if (!pids) return 0;

    int pidCount = proc_listallpids(
        pids,
        pidCapacity * (int)sizeof(pid_t)
    );

    int outputCount = 0;

    for (int i = 0; i < pidCount && outputCount < capacity; i++) {
        pid_t pid = pids[i];
        if (pid <= 0) continue;

        char processName[256] = {0};
        proc_name(pid, processName, sizeof(processName));

        int fdBytes = proc_pidinfo(
            pid, PROC_PIDLISTFDS, 0, NULL, 0
        );

        if (fdBytes <= 0) continue;

        int fdCapacity = fdBytes / sizeof(struct proc_fdinfo) + 32;

        struct proc_fdinfo *fds = calloc(
            fdCapacity,
            sizeof(struct proc_fdinfo)
        );

        if (!fds) continue;

        int actualBytes = proc_pidinfo(
            pid,
            PROC_PIDLISTFDS,
            0,
            fds,
            fdCapacity * sizeof(struct proc_fdinfo)
        );

        int fdCount = actualBytes > 0
            ? actualBytes / sizeof(struct proc_fdinfo)
            : 0;

        for (int j = 0; j < fdCount && outputCount < capacity; j++) {
            if (fds[j].proc_fdtype != PROX_FDTYPE_SOCKET) {
                continue;
            }

            struct socket_fdinfo socketInfo;
            memset(&socketInfo, 0, sizeof(socketInfo));

            int size = proc_pidfdinfo(
                pid,
                fds[j].proc_fd,
                PROC_PIDFDSOCKETINFO,
                &socketInfo,
                sizeof(socketInfo)
            );

            if (size != sizeof(socketInfo)) continue;

            struct socket_info *si = &socketInfo.psi;

            if (si->soi_family != AF_INET &&
                si->soi_family != AF_INET6) {
                continue;
            }

            int proto = si->soi_protocol;

            if (proto != IPPROTO_TCP && proto != IPPROTO_UDP) {
                continue;
            }

            struct in_sockinfo *in = &si->soi_proto.pri_in;

            MacInfoConnection *out = &results[outputCount];
            memset(out, 0, sizeof(*out));

            out->pid = pid;
            out->fd = fds[j].proc_fd;

            snprintf(
                out->process_name,
                sizeof(out->process_name),
                "%s",
                processName
            );

            snprintf(
                out->protocol_name,
                sizeof(out->protocol_name),
                "%s",
                proto == IPPROTO_TCP ? "TCP" : "UDP"
            );

            if (si->soi_family == AF_INET) {
                inet_ntop(
                    AF_INET,
                    &in->insi_laddr.ina_46.i46a_addr4,
                    out->local_address,
                    sizeof(out->local_address)
                );

                inet_ntop(
                    AF_INET,
                    &in->insi_faddr.ina_46.i46a_addr4,
                    out->remote_address,
                    sizeof(out->remote_address)
                );
            } else {
                inet_ntop(
                    AF_INET6,
                    &in->insi_laddr.ina_6,
                    out->local_address,
                    sizeof(out->local_address)
                );

                inet_ntop(
                    AF_INET6,
                    &in->insi_faddr.ina_6,
                    out->remote_address,
                    sizeof(out->remote_address)
                );
            }

            out->local_port = ntohs(in->insi_lport);
            out->remote_port = ntohs(in->insi_fport);

            snprintf(
                out->state,
                sizeof(out->state),
                "%s",
                proto == IPPROTO_TCP
                    ? tcp_state_name(
                        si->soi_proto.pri_tcp.tcpsi_state
                    )
                    : "—"
            );

            outputCount++;
        }

        free(fds);
    }

    free(pids);
    return outputCount;
}
