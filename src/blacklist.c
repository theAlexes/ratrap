#include <stdio.h>
#include <stdlib.h>

void *blocklist_open(void)
{
    return(malloc(0));
}

void blocklist_close(void *it)
{
    free(it);
}
