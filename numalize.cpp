#include <iostream>
#include <unordered_map>
#include <map>

#include "pin.H"

const int MAXTHREADS = 128;

struct pageinfo {
	UINT64 accesses[MAXTHREADS];
	int firstacc;
};

unordered_map<UINT64, pageinfo> pagemap;
map<UINT32, UINT32> pidmap;
PIN_LOCK mem_lock;

VOID memaccess(BOOL is_Read, ADDRINT pc, ADDRINT addr, INT32 size, THREADID threadid)
{
	UINT64 page = addr >> 12;

	if (pagemap.find(page) == pagemap.end()){
		PIN_GetLock(&mem_lock, 0);
		if (pagemap.find(page) == pagemap.end())
			pagemap[page].firstacc = threadid;
		PIN_ReleaseLock(&mem_lock);
	}
	pagemap[page].accesses[threadid]++;
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


VOID Fini(INT32 code, VOID *v)
{
	int real_tid[MAXTHREADS];
	int i = 0;

	for (auto it = pidmap.cbegin(); it != pidmap.cend(); it++)
		real_tid[i++] = it->second;

	int num_threads = i;

	UINT64 num_pages = 0;
	cerr << "nr, addr, firstacc";
	for (int i = 0; i<num_threads; i++)
		cerr << ", T" << i;
	cerr << endl;

	for(auto it = pagemap.begin(); it != pagemap.end(); it++) {
		cerr << num_pages << ", " << it->first << ", " << real_tid[it->second.firstacc];
		for (int i=0; i<num_threads; i++) {
			cerr << ", " << it->second.accesses[real_tid[i]];
		}
		cerr << endl;
		num_pages++;
	}

	cout << "total pages: "<< num_pages << ", memory usage: " << num_pages*4 << " KB" << endl;
}


int main(int argc, char *argv[])
{
	if (PIN_Init(argc,argv)) {return 1;}
	pagemap.reserve(1000000); // 4GByte of mem usage, enough for NAS input C

	PIN_AddThreadStartFunction(ThreadStart, 0);
	INS_AddInstrumentFunction(trace_memory, 0);

	PIN_AddFiniFunction(Fini, 0);
	PIN_InitLock(&mem_lock);

	PIN_StartProgram();
}
