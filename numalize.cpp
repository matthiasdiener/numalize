#include <iostream>
#include <map>


#include "pin.H"


map<UINT64, UINT64> pagemap;
map<UINT64, THREADID> firstacc;

typedef map<UINT64, UINT64>::iterator it_type;


VOID memaccess(BOOL is_Read, ADDRINT pc, ADDRINT addr, INT32 size, THREADID threadid)
{
	UINT64 page = addr >> 12;
	UINT64 acc = __sync_add_and_fetch(&pagemap[page], 1);

	if (acc==1) {
		firstacc[page] = threadid;
		// cout << "Page " << (page) << endl;
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
	int pid = PIN_GetTid();
	// cerr << "Thread " << threadid << " PID " << pid << " registered" << endl;
}

VOID ThreadFini(THREADID threadid, const CONTEXT *ctxt, INT32 code, VOID *v)
{
	// cerr << "Thread " << threadid << " finished" << endl;
}

VOID Fini(INT32 code, VOID *v)
{
	UINT64 num_pages = 0;
	for(it_type it = pagemap.begin(); it != pagemap.end(); it++) {
		cout << "Page: " << it->first << ", Accesses: " << it->second << ", 1st access: tid " << firstacc[it->first] << endl;
		num_pages++;
	}
	cout << "num_pages: "<< num_pages << " memory usage: " << num_pages*4 << " KB" << endl;
}

int main(int argc, char *argv[])
{
	if (PIN_Init(argc,argv)) {return 1;}

	PIN_AddThreadStartFunction(ThreadStart, 0);
	PIN_AddThreadFiniFunction(ThreadFini, 0);

	INS_AddInstrumentFunction(trace_memory, 0);

	PIN_AddFiniFunction(Fini, 0);

	PIN_StartProgram();
}
