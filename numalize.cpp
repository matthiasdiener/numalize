#include <iostream>
#include <sstream>
#include <unordered_map>
#include <map>
#include <array>
#include <cmath>
#include <cstring>
#include <fstream>
#include <unistd.h>

#include <sys/time.h>
#include <sys/resource.h>

#include "pin.H"

const int MAXTHREADS = 1024;
int PAGESIZE;

KNOB<int> COMMSIZE(KNOB_MODE_WRITEONCE, "pintool", "cs", "6", "comm shift in bits");
KNOB<int> INTERVAL(KNOB_MODE_WRITEONCE, "pintool", "i", "0", "print interval (ms) (0=disable)");

KNOB<bool> DOCOMM(KNOB_MODE_WRITEONCE, "pintool", "c", "0", "enable comm detection");
KNOB<bool> DOPAGE(KNOB_MODE_WRITEONCE, "pintool", "p", "0", "enable page usage detection");


int num_threads = 0;

UINT64 comm_matrix[MAXTHREADS][MAXTHREADS]; // comm matrix

unordered_map<UINT64, array<UINT32,2>> commmap; // cache line -> list of tids that previously accesses

array<unordered_map<UINT64, UINT64>, MAXTHREADS+1> pagemap;
array<unordered_map<UINT64, UINT64>, MAXTHREADS+1> ftmap;

map<UINT32, UINT32> pidmap; // pid -> tid

array<UINT64, MAXTHREADS> stacksize; // stack size of each thread in pages
array<UINT64, MAXTHREADS> stackmax;  // tid -> stack base address from file (unpinned application)
map<UINT32, UINT64> stackmap;        // stack base address from pinned application

string img_name;


static inline
VOID inc_comm(int a, int b) {
	if (a!=b-1)
		comm_matrix[a][b-1]++;
}


VOID do_comm(ADDRINT addr, THREADID tid)
{
	UINT64 line = addr >> COMMSIZE;
	tid = tid>=2 ? tid-1 : tid;
	int sh = 1;

	THREADID a = commmap[line][0];
	THREADID b = commmap[line][1];


	if (a == 0 && b == 0)
		sh = 0;
	if (a != 0 && b != 0)
		sh = 2;

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

static inline
UINT64 get_tsc()
{
	#if defined(__i386) || defined(__x86_64__)
		unsigned int lo, hi;
		__asm__ __volatile__ (
			"cpuid \n"
			"rdtsc"
			: "=a"(lo), "=d"(hi) /* outputs */
			: "a"(0)             /* inputs */
			: "%ebx", "%ecx");   /* clobbers*/
	  return ((UINT64)lo) | (((UINT64)hi) << 32);
	#elif defined(__ia64)
		UINT64 r;
		__asm__ __volatile__ ("mov %0=ar.itc" : "=r" (r) :: "memory");
		return r;
	#else
		#error "architecture not supported"
	#endif
}

VOID do_numa(ADDRINT addr, THREADID tid)
{
	UINT64 page = addr >> PAGESIZE;
	tid = tid>=2 ? tid-1 : tid;

	if (pagemap[tid][page]++ == 0)
		ftmap[tid][page] = get_tsc();
}


VOID trace_memory_comm(INS ins, VOID *v)
{
	if (INS_IsMemoryRead(ins))
		INS_InsertCall(ins, IPOINT_BEFORE, (AFUNPTR)do_comm, IARG_MEMORYREAD_EA, IARG_THREAD_ID, IARG_END);

	if (INS_HasMemoryRead2(ins))
		INS_InsertCall(ins, IPOINT_BEFORE, (AFUNPTR)do_comm, IARG_MEMORYREAD2_EA, IARG_THREAD_ID, IARG_END);

	if (INS_IsMemoryWrite(ins))
		INS_InsertCall(ins, IPOINT_BEFORE, (AFUNPTR)do_comm, IARG_MEMORYWRITE_EA, IARG_THREAD_ID, IARG_END);
}

VOID trace_memory_page(INS ins, VOID *v)
{
	if (INS_IsMemoryRead(ins))
		INS_InsertCall(ins, IPOINT_BEFORE, (AFUNPTR)do_numa, IARG_MEMORYREAD_EA, IARG_THREAD_ID, IARG_END);

	if (INS_HasMemoryRead2(ins))
		INS_InsertCall(ins, IPOINT_BEFORE, (AFUNPTR)do_numa, IARG_MEMORYREAD2_EA, IARG_THREAD_ID, IARG_END);

	if (INS_IsMemoryWrite(ins))
		INS_InsertCall(ins, IPOINT_BEFORE, (AFUNPTR)do_numa, IARG_MEMORYWRITE_EA, IARG_THREAD_ID, IARG_END);
}


VOID ThreadStart(THREADID tid, CONTEXT *ctxt, INT32 flags, VOID *v)
{
	__sync_add_and_fetch(&num_threads, 1);

	if (num_threads>=MAXTHREADS+1) {
		cerr << "ERROR: num_threads (" << num_threads << ") higher than MAXTHREADS (" << MAXTHREADS << ")." << endl;
	}

	int pid = PIN_GetTid();
	pidmap[pid] = tid ? tid - 1 : tid;
	stackmap[pid] = PIN_GetContextReg(ctxt, REG_STACK_PTR) >> PAGESIZE;
}


VOID print_matrix()
{
	static long n = 0;
	ofstream f;
	char fname[255];

	if (INTERVAL)
		sprintf(fname, "%s.%06ld.comm.csv", img_name.c_str(), n++);
	else
		sprintf(fname, "%s.full.comm.csv", img_name.c_str());

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
			f << comm_matrix[a][b] + comm_matrix[b][a];
			if (j != num_threads-1)
				f << ",";
		}
		f << endl;
	}
	f << endl;

	f.close();
}


VOID getRealStackBase()
{
	ifstream ifs;
	ifs.open(img_name + ".stackmap");

	string line;
	int tid;
	UINT64 maxaddr, size;

	while (getline(ifs, line)) {
		stringstream lineStream(line);
		lineStream >> tid >> maxaddr >> size;
		stackmax[tid] = maxaddr;
		stacksize[tid] = size;
	}

	ifs.close();
}


UINT64 fixstack(UINT64 pageaddr, int real_tid[], THREADID first)
{
	if (pageaddr < 100 * 1000 * 1000)
		return pageaddr;

	// cout << "pg " << pageaddr << endl;

	for (auto it : stackmap) {
		long diff = (it.second + 1 - pageaddr);
		int tid = real_tid[pidmap[it.first]];
		// cout << "  " << it.second << " " << abs(diff) << endl;
		if ((UINT64)labs(diff) <= stacksize[tid]) {

			int fixup = stackmax[tid] - stackmap[it.first]; //should be stackmap[tid]???

			pageaddr += fixup;
			// cout << "    fixup T" << tid << " " << fixup << ": " << pageaddr-fixup << "->" << pageaddr << endl;

			return pageaddr;
		}
	}

	cout << "STACK MISMATCH " << pageaddr << " T: " << first <<  " rtid: " << real_tid[pidmap[first]] << endl;
	return pageaddr;
}


void print_numa()
{
	int real_tid[MAXTHREADS+1];

	unordered_map<UINT64, array<UINT64, MAXTHREADS+1>> finalmap;
	unordered_map<UINT64, pair<UINT64, UINT32>> finalft;

	int i = 0;

	static long n = 0;
	ofstream f;
	char fname[255];

	if (INTERVAL)
		sprintf(fname, "%s.%06ld.page.csv", img_name.c_str(), n++);
	else
		sprintf(fname, "%s.full.page.csv", img_name.c_str());

	cout << ">>> " << fname << endl;

	getRealStackBase();

	f.open(fname);

	for (auto it : pidmap){
		real_tid[it.second] = i++;
		cout << it.second << "->" << i-1 << " Stack " << stackmap[it.first] << " " << stacksize[i-1] << endl;
	}

	f << "addr,firstacc";
	for (int i = 0; i<num_threads; i++)
		f << ",T" << i;
	f << "\n";


	// determine which thread accessed each page first
	for (int tid = 0; tid<num_threads; tid++) {
		for (auto it : pagemap[tid]) {
			finalmap[it.first][tid] = pagemap[tid][it.first];
			if (finalft[it.first].first == 0 || finalft[it.first].first > ftmap[tid][it.first])
				finalft[it.first] = make_pair(ftmap[tid][it.first], real_tid[tid]);
		}
	}

	// fix stack and print pages to csv
	for(auto it : finalmap) {
		UINT64 pageaddr = fixstack(it.first, real_tid, finalft[it.first].second);
		f << pageaddr << "," << finalft[it.first].second;

		for (int i=0; i<num_threads; i++)
			f << "," << it.second[real_tid[i]];

		f << "\n";
	}

	f.close();
}


VOID mythread(VOID * arg)
{
	while(!PIN_IsProcessExiting()) {
		PIN_Sleep(INTERVAL ? INTERVAL : 100);

		if (INTERVAL == 0)
			continue;

		if (DOCOMM) {
			print_matrix();
			memset(comm_matrix, 0, sizeof(comm_matrix));
		}
		if (DOPAGE) {
			print_numa();
			// for(auto it : pagemap)
			// 	fill(begin(it.second), end(it.second), 0);
		}
	}
}


VOID binName(IMG img, VOID *v)
{
	if (IMG_IsMainExecutable(img))
		img_name = basename(IMG_Name(img).c_str());
}



VOID Fini(INT32 code, VOID *v)
{
	if (DOCOMM)
		print_matrix();
	if (DOPAGE)
		print_numa();

	cout << endl << "MAXTHREADS: " << MAXTHREADS << " COMMSIZE: " << COMMSIZE << " PAGESIZE: " << PAGESIZE << " INTERVAL: " << INTERVAL << endl << endl;
}


int main(int argc, char *argv[])
{
	if (PIN_Init(argc,argv)) return 1;

	PAGESIZE = log2(sysconf(_SC_PAGESIZE));

	if (!DOCOMM && !DOPAGE) {
		cerr << "ERROR: need to choose at least one of communication (-c) or page usage (-p) detection" << endl;
		cerr << endl << KNOB_BASE::StringKnobSummary() << endl;
		return 1;
	}

	THREADID t = PIN_SpawnInternalThread(mythread, NULL, 0, NULL);
	if (t!=1)
		cerr << "ERROR internal thread " << t << endl;

	cout << endl << "MAXTHREADS: " << MAXTHREADS << " COMMSIZE: " << COMMSIZE << " PAGESIZE: " << PAGESIZE << " INTERVAL: " << INTERVAL << endl << endl;

	if (DOPAGE)
		INS_AddInstrumentFunction(trace_memory_page, 0);

	if (DOCOMM) {
		INS_AddInstrumentFunction(trace_memory_comm, 0);
		commmap.reserve(100*1000*1000);
	}

	IMG_AddInstrumentFunction(binName, 0);
	PIN_AddThreadStartFunction(ThreadStart, 0);
	PIN_AddFiniFunction(Fini, 0);

	PIN_StartProgram();
}
