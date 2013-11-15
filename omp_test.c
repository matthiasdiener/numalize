#include <stdio.h>
#include <omp.h>
#include <sys/types.h>
#define _GNU_SOURCE
#include <unistd.h>
#include <sys/syscall.h>


int main(int argc, char const *argv[])
{

	#pragma omp parallel
	{
		int tid = omp_get_thread_num();
		int pid = syscall(SYS_gettid);
		printf("thread %d pid %d\n", tid, pid);
	}

}
