#include <iostream>
#include <unordered_map>
#include <map>
#include <array>
#include <cmath>
#include <cstring>
#include <fstream>

#include "pin.H"

const int MAXTHREADS = 1024;
const int PAGESIZE = 12;
const int COMMSIZE = 6;

int num_threads = 0;

UINT64 matrix[MAXTHREADS][MAXTHREADS];

unordered_map<UINT64, array<UINT64, MAXTHREADS+1>> pagemap;

unordered_map<UINT64, array<UINT32,2>> commmap;

map<UINT32, UINT32> pidmap;
PIN_LOCK lock;

unsigned long nacc = 0;
void print_matrix(int);
void print_numa();


static inline
void inc_comm(int a, int b) {
	matrix[a][b-1]++;
}

void do_comm(THREADID tid, ADDRINT addr)
{
	UINT64 line = addr >> COMMSIZE;
	int sh = 1;

	// convert to
	// a = commmap[line][0]; b = commmap[line][1];

	// PIN_GetLock(&lock, 0);

	if (commmap[line][0] == 0 && commmap[line][1] == 0)
		sh= 0;
	if (commmap[line][0] != 0 && commmap[line][1] != 0)
		sh= 2;

	switch (sh) {
		case 0: /* no one accessed page before, store accessing thread in pos 0 */
			commmap[line][0] = tid+1;
			break;

		case 1: /* one previous access => needs to be in pos 0 */
			if (commmap[line][0] != tid+1) {
				inc_comm(tid, commmap[line][0]);
				commmap[line][1] = commmap[line][0];
				commmap[line][0] = tid+1;
			}
			break;

		case 2: // two previous accesses
			if (commmap[line][0] != tid+1 && commmap[line][1] != tid+1) {
				inc_comm(tid, commmap[line][0]);
				inc_comm(tid, commmap[line][1]);
				commmap[line][1] = commmap[line][0];
				commmap[line][0] = tid+1;
			} else if (commmap[line][0] == tid+1) {
				inc_comm(tid, commmap[line][1]);
			} else if (commmap[line][1] == tid+1) {
				inc_comm(tid, commmap[line][0]);
				commmap[line][1] = commmap[line][0];
				commmap[line][0] = tid+1;
			}

			break;
	}
	// PIN_ReleaseLock(&lock);
}

void do_numa(THREADID tid, ADDRINT addr)
{
	UINT64 page = addr >> PAGESIZE;
	if (pagemap[page][MAXTHREADS] == 0)
		__sync_bool_compare_and_swap(&pagemap[page][MAXTHREADS], 0, tid+1);

	pagemap[page][tid]++;
}


VOID memaccess(BOOL is_Read, ADDRINT pc, ADDRINT addr, INT32 size, THREADID tid)
{
	do_comm(tid, addr);
	// do_numa(tid, addr);

	int n = __sync_add_and_fetch(&nacc, 1);

	if (n % 50000000 == 0) {
		print_matrix(num_threads);
		// print_numa();
		// memset(&matrix, 0, sizeof(matrix));
	}
}

VOID trace_memory(INS ins, VOID *v)
{
	if (INS_IsMemoryRead(ins)) {
		INS_InsertCall( ins, IPOINT_BEFORE, (AFUNPTR)memaccess, IARG_BOOL, true, IARG_INST_PTR, IARG_MEMORYREAD_EA, IARG_MEMORYREAD_SIZE, IARG_THREAD_ID, IARG_END);
	}
	if (INS_HasMemoryRead2(ins)) {
		INS_InsertCall( ins, IPOINT_BEFORE, (AFUNPTR)memaccess, IARG_BOOL, true, IARG_INST_PTR, IARG_MEMORYREAD2_EA, IARG_MEMORYREAD_SIZE, IARG_THREAD_ID, IARG_END);
	}
	if (INS_IsMemoryWrite(ins)) {
		INS_InsertCall( ins, IPOINT_BEFORE, (AFUNPTR)memaccess, IARG_BOOL, false, IARG_INST_PTR, IARG_MEMORYWRITE_EA, IARG_MEMORYWRITE_SIZE, IARG_THREAD_ID, IARG_END);
	}
}


VOID ThreadStart(THREADID threadid, CONTEXT *ctxt, INT32 flags, VOID *v)
{
	__sync_add_and_fetch(&num_threads, 1);
	int pid = PIN_GetTid();
	pidmap[pid] = threadid;
}

VOID print_matrix(int num_threads)
{
	static long n = 0;
	ofstream f;
	string fname = to_string(n++) + ".csv";

	cout << fname << endl;

	f.open(fname);
	for (int i = num_threads-1; i>=0; i--) {
		for (int j = 0; j<num_threads; j++) {
			f << matrix[i][j] + matrix[j][i];
			if (j != num_threads-1)
				f << ",";
		}
		f << endl;
	}
	f << endl;

	f.close();
}


void print_numa()
{
	int real_tid[MAXTHREADS+1];
	int i = 0;

	for (auto it : pidmap)
		real_tid[it.second] = i++;


	UINT64 num_pages = 0;
	cout << "nr, addr, firstacc";
	for (int i = 0; i<num_threads; i++)
		cout << ", T" << i;
	cout << endl;


	for(auto it : pagemap) {
		cout << num_pages << ", " << it.first << ", " << real_tid[it.second[MAXTHREADS]-1];

		for (int i=0; i<num_threads; i++)
			cout << ", " << it.second[real_tid[i]];

		cout << endl;
		num_pages++;
	}
	cout << "#threads: " << num_threads << ", total pages: "<< num_pages << ", memory usage: " << num_pages*pow(2,PAGESIZE)/1024 << " KB, nacc: " << nacc << endl;
}



VOID Fini(INT32 code, VOID *v)
{
	print_matrix(num_threads);
	// print_numa();
}


int main(int argc, char *argv[])
{
	if (PIN_Init(argc,argv)) return 1;

	PIN_InitLock(&lock);

	pagemap.reserve(1000000); // ~4GByte of mem usage, enough for NAS input C
	commmap.reserve(100000000);

	PIN_AddThreadStartFunction(ThreadStart, 0);
	INS_AddInstrumentFunction(trace_memory, 0);

	PIN_AddFiniFunction(Fini, 0);

	PIN_StartProgram();
}
