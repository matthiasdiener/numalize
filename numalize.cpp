#include <iostream>
#include <unordered_map>
#include <map>
#include <array>
#include <cmath>
#include <cstring>
#include <fstream>

#include "pin.H"

const int MAXTHREADS = 1024;

KNOB<int> COMMSIZE(KNOB_MODE_WRITEONCE, "pintool", "c", "6", "comm shift in bits");
KNOB<int> PAGESIZE(KNOB_MODE_WRITEONCE, "pintool", "p", "12", "page size in bits");

int num_threads = 0;

UINT64 matrix[MAXTHREADS][MAXTHREADS];

unordered_map<UINT64, array<UINT64, MAXTHREADS+1>> pagemap;

unordered_map<UINT64, array<UINT32,2>> commmap;

array<UINT64, MAXTHREADS> t_acc;
UINT64 ncomm = 0;
// UINT64 t_acc [MAXTHREADS];

map<UINT32, UINT32> pidmap;
PIN_LOCK lock;

void print_matrix();
void print_numa();


VOID mythread(VOID * arg)
{
	while(!PIN_IsProcessExiting()) {
		PIN_Sleep(100);
		print_matrix();
		memset(matrix, 0, sizeof(matrix));
	}
}

static inline
VOID inc_comm(int a, int b) {
	if (a!=b-1)
		matrix[a][b-1]++;
}

VOID do_comm(THREADID tid, ADDRINT addr)
{
	UINT64 line = addr >> COMMSIZE;
	int sh = 1;

	THREADID a = commmap[line][0];
	THREADID b = commmap[line][1];
	// THREADID tid = threadid ? threadid - 1 : threadid;


	if (a == 0 && b == 0)
		sh= 0;
	if (a != 0 && b != 0)
		sh= 2;

	switch (sh) {
		case 0: /* no one accessed line before, store accessing thread in pos 0 */
			commmap[line][0] = tid+1;
			break;

		case 1: /* one previous access => needs to be in pos 0 */
			if (a != tid+1) {
				inc_comm(tid, a);
				commmap[line][1] = a;
				commmap[line][0] = tid+1;
			}
			break;

		case 2: // two previous accesses
			if (a != tid+1 && b != tid+1) {
				inc_comm(tid, a);
				inc_comm(tid, b);
				commmap[line][1] = a;
				commmap[line][0] = tid+1;
			} else if (a == tid+1) {
				inc_comm(tid, b);
			} else if (b == tid+1) {
				inc_comm(tid, a);
				commmap[line][1] = a;
				commmap[line][0] = tid+1;
			}

			break;
	}
}

VOID do_numa(THREADID threadid, ADDRINT addr)
{
	THREADID tid = threadid ? threadid - 1 : threadid;
	UINT64 page = addr >> PAGESIZE;
	if (pagemap[page][MAXTHREADS] == 0)
		__sync_bool_compare_and_swap(&pagemap[page][MAXTHREADS], 0, tid+1);

	pagemap[page][tid]++;
}


VOID memaccess(ADDRINT addr, THREADID tid)
{
	do_comm(tid>=2 ? tid-1 : tid, addr);
	// do_numa(tid, addr);
}

VOID trace_memory(INS ins, VOID *v)
{
	if (INS_IsMemoryRead(ins)) {
		INS_InsertCall(ins, IPOINT_BEFORE, (AFUNPTR)memaccess, IARG_MEMORYREAD_EA, IARG_THREAD_ID, IARG_END);
	}
	if (INS_HasMemoryRead2(ins)) {
		INS_InsertCall(ins, IPOINT_BEFORE, (AFUNPTR)memaccess, IARG_MEMORYREAD2_EA, IARG_THREAD_ID, IARG_END);
	}
	if (INS_IsMemoryWrite(ins)) {
		INS_InsertCall(ins, IPOINT_BEFORE, (AFUNPTR)memaccess, IARG_MEMORYWRITE_EA, IARG_THREAD_ID, IARG_END);
	}
}


VOID ThreadStart(THREADID threadid, CONTEXT *ctxt, INT32 flags, VOID *v)
{
	__sync_add_and_fetch(&num_threads, 1);
	int pid = PIN_GetTid();
	pidmap[pid] = threadid ? threadid - 1 : threadid;
}

VOID print_matrix()
{
	static long n = 0;
	ofstream f;
	string fname = to_string(n++) + ".csv";

	int real_tid[MAXTHREADS+1];
	int i = 0, a, b;

	for (auto it : pidmap)
		real_tid[it.second] = i++;

	cout << fname << endl;

	f.open(fname);
	for (int i = num_threads-1; i>=0; i--) {
		a = real_tid[i];
		for (int j = 0; j<num_threads; j++) {
			b = real_tid[j];
			f << matrix[a][b] + matrix[b][a];
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
	cout << "#threads: " << num_threads << ", total pages: "<< num_pages << ", memory usage: " << num_pages*pow(2,(double)PAGESIZE)/1024 << " KB, nacc: " << endl;
}



VOID Fini(INT32 code, VOID *v)
{
	print_matrix();
	// print_numa();
}


int main(int argc, char *argv[])
{
	if (PIN_Init(argc,argv)) return 1;

	THREADID t = PIN_SpawnInternalThread(mythread, NULL, 0, NULL);
	if (t!=1)
		cerr << "ERROR " << t << endl;

	PIN_InitLock(&lock);

	pagemap.reserve(1000000); // ~4GByte of mem usage, enough for NAS input C
	commmap.reserve(100000000);

	PIN_AddThreadStartFunction(ThreadStart, 0);
	INS_AddInstrumentFunction(trace_memory, 0);

	PIN_AddFiniFunction(Fini, 0);

	PIN_StartProgram();
}
