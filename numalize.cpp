#include <iostream>
#include <unordered_map>

#include "pin.H"

const int MAXTHREADS = 128;

struct pageinfo {
	UINT64 accesses[MAXTHREADS];
	int firstacc;
};

unordered_map<UINT64, pageinfo> pagemap;
PIN_LOCK mem_lock, tid_lock;
int num_threads = 0;

VOID memaccess(BOOL is_Read, ADDRINT pc, ADDRINT addr, INT32 size, THREADID threadid)
{
	UINT64 page = addr >> 12;

	if (pagemap.find(page) == pagemap.end() ){
		PIN_GetLock(&mem_lock, 0);
		if (pagemap.find(page) == pagemap.end() )
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
	PIN_GetLock(&tid_lock, threadid);

	static int prev_pid = -1;
	int pid = PIN_GetTid();
	cout << "TID: " << threadid << " PID: " << pid << endl;
	if (prev_pid>=pid)
		cout << "XXX XXX XXX WRONG! XXX XXX XXX" << endl;
	num_threads++;
	prev_pid = pid;
	PIN_ReleaseLock(&tid_lock);
}


VOID Fini(INT32 code, VOID *v)
{
	UINT64 num_pages = 0;
	cerr << "nr, addr, firstacc";
	for (int i = 0; i<num_threads; i++)
		cerr << ", T" << i;
	cerr << endl;

	for(auto it = pagemap.cbegin(); it != pagemap.cend(); it++) {
		cerr << num_pages << ", " << it->first << ", " << it->second.firstacc;
		for (int i=0; i<num_threads; i++) {
			cerr << ", " << it->second.accesses[i];
		}
		cerr << endl;
		num_pages++;
	}

	cout << "total pages: "<< num_pages << ", memory usage: " << num_pages*4 << " KB" << endl;
}


int main(int argc, char *argv[])
{
	if (PIN_Init(argc,argv)) {return 1;}
	pagemap.reserve(1000000); //4GByte of mem usage, enough for NAS input C

	PIN_AddThreadStartFunction(ThreadStart, 0);

	INS_AddInstrumentFunction(trace_memory, 0);

	PIN_AddFiniFunction(Fini, 0);
	PIN_InitLock(&mem_lock);
	PIN_InitLock(&tid_lock);

	PIN_StartProgram();
}
