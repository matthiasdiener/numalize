#include <iostream>
#include <unordered_map>
#include <map>
#include <array>
#include <cmath>

#include "pin.H"

const int MAXTHREADS = 1024;
const int PAGESIZE = 12;
const int COMMSIZE = 6;

UINT64 matrix[MAXTHREADS][MAXTHREADS];

unordered_map<UINT64, array<UINT64, MAXTHREADS+1>> pagemap;

unordered_map<UINT64, THREADID> commmap;

map<UINT32, UINT32> pidmap;



VOID memaccess(BOOL is_Read, ADDRINT pc, ADDRINT addr, INT32 size, THREADID threadid)
{
	UINT64 page = addr >> PAGESIZE;
	UINT64 line = addr >> COMMSIZE;

	if (commmap[line] > 0 && commmap[line] != threadid+1)
		matrix[commmap[line]-1][threadid]++;

	commmap[line] = threadid+1;

	// if (pagemap[page][MAXTHREADS] == 0)
	// 	__sync_bool_compare_and_swap(&pagemap[page][MAXTHREADS], 0, threadid+1);

	// pagemap[page][threadid]++;
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
	int pid = PIN_GetTid();
	pidmap[pid] = threadid;
}

VOID print_matrix(int num_threads)
{
	for (int i = num_threads-1; i>=0; i--) {
		for (int j = 0; j<num_threads; j++) {
			cout << matrix[i][j] + matrix[j][i];
			if (j != num_threads-1)
				cout << ",";
		}
		cout << endl;
	}
}


VOID Fini(INT32 code, VOID *v)
{

	int real_tid[MAXTHREADS+1];
	int i = 0;

	for (auto it : pidmap)
		real_tid[it.second] = i++;

	int num_threads = i;


	UINT64 num_pages = 0;
	cerr << "nr, addr, firstacc";
	for (int i = 0; i<num_threads; i++)
		cerr << ", T" << i;
	cerr << endl;


	for(auto it : pagemap) {
		cerr << num_pages << ", " << it.first << ", " << real_tid[it.second[MAXTHREADS]-1];

		for (int i=0; i<num_threads; i++)
			cerr << ", " << it.second[real_tid[i]];

		cerr << endl;
		num_pages++;
	}

	print_matrix(num_threads);

	cout << "#threads: " << num_threads << ", total pages: "<< num_pages << ", memory usage: " << num_pages*pow(2,PAGESIZE)/1024 << " KB" << endl;
}


int main(int argc, char *argv[])
{
	if (PIN_Init(argc,argv)) return 1;

	pagemap.reserve(1000000); // ~4GByte of mem usage, enough for NAS input C
	commmap.reserve(100000000);

	PIN_AddThreadStartFunction(ThreadStart, 0);
	INS_AddInstrumentFunction(trace_memory, 0);

	PIN_AddFiniFunction(Fini, 0);

	PIN_StartProgram();
}
