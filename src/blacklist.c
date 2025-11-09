#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>

struct blacklist {};

struct blacklist *
blacklist_open(void)
{
    void *handle = (struct blacklist *)malloc(sizeof(struct blacklist));
    fprintf(stderr, "opening blocklist, handle %p\n", handle);
    return handle;
}

void
blacklist_close(struct blacklist *it)
{
    fprintf(stderr, "closing blocklist, handle %p\n", it);
    free(it);
}

int
blacklist_sa_r(struct blacklist *handle, int action, int fd,
               const struct sockaddr *sa, socklen_t salen, const char *msg)
{
    char buf[INET6_ADDRSTRLEN];
    const char *ok = NULL;
    fprintf(stderr, "blocklisting with handle %p: action %d, fd %d, salen %d\n", handle, action, fd, salen);
    switch(sa->sa_family) {
    case AF_INET:
        {
            const struct sockaddr_in *sin = (const struct sockaddr_in *)sa;
            ok = inet_ntop(sa->sa_family, (void*)(&sin->sin_addr), buf, INET6_ADDRSTRLEN);
        }
        break;
    case AF_INET6:
        {
            const struct sockaddr_in6 *sin6 = (const struct sockaddr_in6 *)sa;
            ok = inet_ntop(sa->sa_family, (void*)(&sin6->sin6_addr), buf, INET6_ADDRSTRLEN);
        }
        break;
    default:
        fprintf(stderr, "blocklist with handle %p: unknown sa_family %d", handle, sa->sa_family);
        errno = EINVAL;
        return -1;
    }
    if(!ok) {
        fprintf(stderr, "blocklist with handle %p: did not convert sockaddr: %s", handle, strerror(errno));
        return -1;
    }
    if (strcmp(buf, "8.8.8.8") == 0 && handle) {
        fprintf(stderr, "faking a connection reset to test fallback\n");
        errno = ECONNRESET;
        return -1;
    }
    fprintf(stderr, "sockaddr: %s\n", buf);
    fprintf(stderr, "message: %s\n", msg);
    return 0;
}

int
blacklist_sa(int action, int fd, const struct sockaddr *sa,
             socklen_t salen, const char *msg)
{
    return blacklist_sa_r(NULL, action, fd, sa, salen, msg);
}
