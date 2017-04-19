#include <iostream>
#include <unordered_map>
#include <map>
#include <fstream>
#include <string>
#include <algorithm>

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>

#include <sys/time.h>
#include <sys/resource.h>

#include <cstring>
#include <cmath>

#include <libelf.h>
// #include <libelf/libelf.h>
// #define __LIBELF_SYMBOL_VERSIONS 0
// #define __LIBELF_INTERNAL__ 0
// #include <gelf.h>
#include <execinfo.h>

#include "pin.H"

const int MAXTHREADS = 1024;
unsigned int MYPAGESIZE;

KNOB<int> COMMSIZE(KNOB_MODE_WRITEONCE, "pintool", "cs", "6", "comm shift in bits");
KNOB<int> INTERVAL(KNOB_MODE_WRITEONCE, "pintool", "i", "0", "print interval (ms) (0=disable)");

KNOB<bool> DOCOMM(KNOB_MODE_WRITEONCE, "pintool", "c", "0", "enable comm detection");
KNOB<bool> DOPAGE(KNOB_MODE_WRITEONCE, "pintool", "p", "0", "enable page usage detection");

int num_threads = 0;

ofstream fstructStream;

struct alloc {
	string loc; // Location in code where allocated
	string name; // Name of data structure
	ADDRINT addr; // Starting page address (shifted to page size)
	ADDRINT size; // Size in bytes
	THREADID tid; // Thread that performed allocation
};


vector <struct alloc> allocations;
struct alloc tmp_allocs[MAXTHREADS+1];

// Stack size in pages
UINT64 stack_size = 1;

// communication matrix
UINT64 comm_matrix[MAXTHREADS][MAXTHREADS];

struct TIDlist {
	THREADID first;
	THREADID second;
} TIDlist;

// mapping of cache line to a list of TIDs that previously accessed it
unordered_map<UINT64, struct TIDlist> commmap;

// mapping of page to number of accesses to it, indexed by TID
unordered_map<UINT64, UINT64> pagemap [MAXTHREADS+1];

// mapping of page to time stamp of first touch, indexed by TID
unordered_map<UINT64, pair<UINT64, string>> ftmap   [MAXTHREADS+1];

// Mapping of PID to TID (for numbering threads correctly)
map<UINT32, UINT32> pidmap;

// Binary name
string img_name;

// adjust thread ID for extra internal Pin thread that this tool creates
static inline
THREADID real_tid(THREADID tid)
{
	return tid >= 2 ? tid-1 : tid;
}

static inline
VOID inc_comm(int a, int b)
{
	if (a!=b-1)
		comm_matrix[a][b-1]++;
}

VOID do_comm(ADDRINT addr, THREADID tid)
{
	if (num_threads < 2)
		return;
	UINT64 line = addr >> COMMSIZE;
	tid = real_tid(tid);
	int sh = 1;

	THREADID a = commmap[line].first;
	THREADID b = commmap[line].second;

	if (a == 0 && b == 0)
		sh = 0;
	if (a != 0 && b != 0)
		sh = 2;

	switch (sh) {
		case 0: // no one accessed line before, store accessing thread in pos 0
			commmap[line].first = tid+1;
			break;

		case 1: // one previous access => needs to be in pos 0
			// if (a != tid+1) {
				inc_comm(tid, a);
				commmap[line].first = tid+1;
				commmap[line].second = a;
			// }
			break;

		case 2: // two previous accesses
			// if (a != tid+1 && b != tid+1) {
				inc_comm(tid, a);
				inc_comm(tid, b);
				commmap[line].first = tid+1;
				commmap[line].second = a;
			// } else if (a == tid+1) {
			//  inc_comm(tid, b);
			// } else if (b == tid+1) {
			//  inc_comm(tid, a);
			//  commmap[line].first = tid+1;
			//  commmap[line].second = a;
			// }

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
	#elif defined(__powerpc__)
		UINT64 hi, lo, tmp;
		__asm__ volatile(
			"0:\n"
			"mftbu   %0 \n"
			"mftb    %1 \n"
			"mftbu   %2 \n"
			"cmpw    %2,%0 \n"
			"bne     0b \n"
			: "=r"(hi),"=r"(lo),"=r"(tmp) );
		return ((UINT64)lo) | (((UINT64)hi) << 32);
	#else
		#error "architecture not supported"
	#endif
}

bool line_is_alloc(const string &line)
{
	if (line.find(".reserve")!=string::npos ||
		line.find(".resize")!=string::npos ||
		line.find("new")!=string::npos ||
		line.find("malloc")!=string::npos ||
		line.find("calloc")!=string::npos ||
		0)
		return true;
	return false;
}

string find_location(const CONTEXT *ctxt)
{
	string res = "";
	void* buf[128];

	PIN_LockClient();

	int nptrs = PIN_Backtrace(ctxt, buf, sizeof(buf)/sizeof(buf[0]));
	char** bt = backtrace_symbols(buf, nptrs);


	for (int i = nptrs-1; i >= 0; i--) {
		res += bt[i];
		res += " ";

		string line=bt[i];
		size_t start = line.find("(");
		if (start!=string::npos && line.substr(start+1, 4) != "/usr") {
			size_t end = line.find(":");
			string file = line.substr(start+1,end-start-1);
			size_t endf = line.find(")");
			int linenum = Uint64FromString(line.substr(end+1, endf-end-1));

			ifstream fstr(file.c_str());
			string l;
	        for(int i=0; i< linenum; ++i)
	            getline(fstr, l);

	        if (line_is_alloc(l)) {
		        cout << l << endl;
		        PIN_UnlockClient();
		        return line.substr(start+1, endf-start-1);
	        }
	        fstr.close();
		}



	}

	PIN_UnlockClient();
	return res;
}


VOID do_numa(const CONTEXT *ctxt, ADDRINT addr, THREADID tid)
{
	UINT64 page = addr >> MYPAGESIZE;
	tid = real_tid(tid);

	if (pagemap[tid][page]++ == 0) { //first touch
		UINT64 tsc = get_tsc();
		string fname;
		int col, line;
		PIN_LockClient();
		PIN_GetSourceLocation(PIN_GetContextReg(ctxt,REG_INST_PTR), &col, &line, &fname);
		PIN_UnlockClient();
		if (fname == "")
			fname = "unknown.loc";
		else
			fname += ":" + decstr(line);
		ftmap[tid][page] = make_pair(tsc, fname);
	}
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
		INS_InsertCall(ins, IPOINT_BEFORE, (AFUNPTR)do_numa, IARG_CONST_CONTEXT, IARG_MEMORYREAD_EA, IARG_THREAD_ID, IARG_END);

	if (INS_HasMemoryRead2(ins))
		INS_InsertCall(ins, IPOINT_BEFORE, (AFUNPTR)do_numa, IARG_CONST_CONTEXT, IARG_MEMORYREAD2_EA, IARG_THREAD_ID, IARG_END);

	if (INS_IsMemoryWrite(ins))
		INS_InsertCall(ins, IPOINT_BEFORE, (AFUNPTR)do_numa, IARG_CONST_CONTEXT, IARG_MEMORYWRITE_EA, IARG_THREAD_ID, IARG_END);
}


VOID ThreadStart(THREADID tid, CONTEXT *ctxt, INT32 flags, VOID *v)
{
	__sync_add_and_fetch(&num_threads, 1);

	if (num_threads>=MAXTHREADS+1) {
		cerr << "ERROR: num_threads (" << num_threads << ") higher than MAXTHREADS (" << MAXTHREADS << ")." << endl;
	}

	int pid = PIN_GetTid();
	pidmap[pid] = tid ? tid - 1 : tid;

	struct alloc stacktmp;
	stacktmp.tid = real_tid(tid);
	stacktmp.addr = (PIN_GetContextReg(ctxt, REG_STACK_PTR) >> MYPAGESIZE) - stack_size;
	stacktmp.loc = "unknown.loc";
	stacktmp.name = "Stack";
	stacktmp.size = stack_size << MYPAGESIZE;
	allocations.push_back(stacktmp);
}


VOID print_comm()
{
	static long n = 0;
	ofstream f;
	char fname[255];

	int cs = COMMSIZE;

	if (INTERVAL)
		sprintf(fname, "%s.%06ld.%d.comm.csv", img_name.c_str(), n++, cs);
	else
		sprintf(fname, "%s.full.%d.comm.csv", img_name.c_str(), cs);

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


struct alloc find_structure(ADDRINT addr)
{
	for (auto it : allocations) {
		if (addr >= it.addr && addr <= it.addr + (it.size >> MYPAGESIZE))
			return it;
	}
	struct alloc tmp;
	tmp.name = "unknown.name";
	tmp.loc = "unknown.loc";
	return tmp;
}


void print_page()
{
	int final_tid[MAXTHREADS+1], i=0;

	for (auto it : pidmap)
		final_tid[it.second] = i++;

	sort(allocations.begin(), allocations.end(), [](struct alloc const& a, struct alloc const& b) {return a.addr < b.addr;} );

	for (auto it : allocations)
		cout << final_tid[it.tid] << " " << it.addr << " " << it.size << " " << it.name << endl;

	unordered_map<UINT64, vector<UINT64>> finalmap;
	unordered_map<UINT64, pair<UINT64, UINT32>> finalft;

	string fname = img_name + ".";

	if (INTERVAL) {
		static long n = 0;
		fname += StringDec(n++, 6, '0') + ".page.csv";
	}
	else
		fname += "full.page.csv";

	cout << ">>> " << fname << endl;

	ofstream f(fname.c_str());

	f << "page.address,alloc.thread,alloc.location,firsttouch.thread,firsttouch.location,structure.name";
	for (int i = 0; i<num_threads; i++)
		f << ",T" << i;
	f << "\n";

	// determine which thread accessed each page first
	for (int tid = 0; tid<num_threads; tid++) {
		for (auto it : pagemap[tid]) {
			finalmap[it.first].resize(MAXTHREADS);
			finalmap[it.first][tid] = pagemap[tid][it.first];
			if (finalft[it.first].first == 0 || finalft[it.first].first > ftmap[tid][it.first].first)
				finalft[it.first] = make_pair(ftmap[tid][it.first].first, tid);
		}
	}

	// write pages to csv
	for(auto it : finalmap) {
		UINT64 pageaddr = it.first;
		struct alloc tmp = find_structure(pageaddr);

		f << pageaddr;
		f << "," << final_tid[tmp.tid];
		f << "," << tmp.loc;
		f << "," << final_tid[finalft[pageaddr].second];
		f << "," << ftmap[finalft[pageaddr].second][pageaddr].second;

		if (tmp.name == "Stack")
			tmp.name = "Stack.T" + decstr(final_tid[tmp.tid]);
		if (tmp.name == "")
			tmp.name = "unknown.name";

		f << "," << tmp.name;

		for (int i=0; i<num_threads; i++)
			f << "," << it.second[final_tid[i]];

		f << "\n";
	}

	f.close();
}


VOID mythread(VOID * arg)
{
	while(1) {
		PIN_Sleep(INTERVAL ? INTERVAL : 100);

		if (INTERVAL == 0)
			continue;

		if (DOCOMM) {
			print_comm();
			memset(comm_matrix, 0, sizeof(comm_matrix));
		}
		if (DOPAGE) {
			print_page();
			// for(auto it : pagemap)
			//  fill(begin(it.second), end(it.second), 0);
		}
	}
}


// //retrieve structures names address and size
// int getStructs(const char* file);
// string get_struct_name(string str, int ln, string fname, int rec);

// string get_complex_struct_name(int ln, string fname)
// {
//     ifstream fstr(fname);
//     int lastmalloc=0;
//     // Find the real malloc line
//     string line,allocstr;
//     for(int i=0; i< ln; ++i)
//     {
//         getline(fstr, line);
//         if(line.find("alloc")!=string::npos)
//         {
//             allocstr=line;
//             lastmalloc=i;
//         }
//     }
//     fstr.close();
//     if(allocstr.find("=")==string::npos)
//     {
//         /*
//          * Allocation split among several lines,
//          * we assume it looks like
//          *  foo =
//          *      malloc(bar)
//          *  Note:
//          *      if foo and '=' are on different lines, we will give up
//          */
//         fstr.open(fname);
//         for(int i=0; i< lastmalloc; ++i)
//         {
//             getline(fstr, line);
//             if(line.find("=")!=string::npos)
//                 allocstr=line;
//         }
//         fstr.close();
//     }
//     //Now that we have the good line, extract the struct name
//     return get_struct_name(allocstr, ln, fname, 1/*forbid recursive calls*/);
// }

// string get_struct_name(string str, int ln, string fname, int hops)
// {
//     if( str.find(string("}"))!=string::npos && hops==0) {
//      cout << "HERE" << endl;
//          backtrace();
//         return get_complex_struct_name(ln, fname); //Return Ip is not malloc line
//     }
//     // Remove everything after first '='
//     string ret = str.substr(0,str.find('='));

//     //remove trailing whitespaces
//     while(ret.back()==' ')
//         ret.resize(ret.size()-1);

//     // Take the last word
//     ret=ret.substr(ret.find_last_of(string(" )*"))+1);

//     // Our search has failed, it will be an anonymous malloc
//     if(ret.compare("")==0) {
//         cerr << "Unable to find a suitable alloc name for file  "
//             << fname << " line: " << ln << endl;
//         return string("AnonymousStruct");
//     }
//     cout << "X:  " << ret << endl;
//     return ret;
// }



VOID PREMALLOC(ADDRINT retip, THREADID tid, const CONTEXT *ctxt, ADDRINT size)
{
	tid = real_tid(tid);

	if (size < 1024*1024)
		return;

	string loc = find_location(ctxt);

	if (tmp_allocs[tid].addr == 0) {
		tmp_allocs[tid].addr = 12341234;
		tmp_allocs[tid].tid  = real_tid(tid);
		tmp_allocs[tid].size = size;
		tmp_allocs[tid].loc  = loc;
		tmp_allocs[tid].name = "";
	} else {
		cerr << "BUGBUGBUGBUG PREMALLOC " << tid << endl;
	}
}

VOID POSTMALLOC(ADDRINT ret, THREADID tid)
{
	if (tmp_allocs[tid].addr == 12341234) {
		tmp_allocs[tid].addr = ret >> MYPAGESIZE;
		allocations.push_back(tmp_allocs[tid]);

		cout << "::: ALLOC: " << tid << " " << tmp_allocs[tid].addr << " " << tmp_allocs[tid].size << " " << tmp_allocs[tid].loc << endl;
		tmp_allocs[tid].addr = 0;
	} else {
		// cerr << "BUGBUGBUGBUG POSTMALLOC " << tid << endl;
	}
}

void getStructs(const char *name);


VOID InitMain(IMG img, VOID *v)
{
	if (IMG_IsMainExecutable(img)) {
		img_name = basename(IMG_Name(img).c_str());
		getStructs(img_name.c_str());
	}

	struct rlimit sl;
	int ret = getrlimit(RLIMIT_STACK, &sl);
	if (ret == -1)
		cerr << "Error getting stack size. errno: " << errno << endl;
	else
		stack_size = sl.rlim_cur >> MYPAGESIZE;

	RTN mallocRtn = RTN_FindByName(img, "malloc");
	if (RTN_Valid(mallocRtn))
	{
		RTN_Open(mallocRtn);

		RTN_InsertCall(mallocRtn, IPOINT_BEFORE, (AFUNPTR)PREMALLOC,                IARG_RETURN_IP, IARG_THREAD_ID, IARG_CONST_CONTEXT,                IARG_FUNCARG_ENTRYPOINT_VALUE, 0,  IARG_END);
		RTN_InsertCall(mallocRtn, IPOINT_AFTER, (AFUNPTR)POSTMALLOC,                IARG_FUNCRET_EXITPOINT_VALUE, IARG_THREAD_ID, IARG_END);

		RTN_Close(mallocRtn);
	}
}



VOID Fini(INT32 code, VOID *v)
{
	if (DOCOMM)
		print_comm();
	if (DOPAGE)
		print_page();

	cout << endl << "MAXTHREADS: " << MAXTHREADS << " COMMSIZE: " << COMMSIZE << " PAGESIZE: " << MYPAGESIZE << " INTERVAL: " << INTERVAL << " NUM_THREADS: " << num_threads << endl << endl;
}


int main(int argc, char *argv[])
{
	PIN_InitSymbols();
	if (PIN_Init(argc,argv)) return 1;

	MYPAGESIZE = log2(sysconf(_SC_PAGESIZE));

	if (!DOCOMM && !DOPAGE) {
		cerr << "ERROR: need to choose at least one of communication (-c) or page usage (-p) detection" << endl;
		cerr << endl << KNOB_BASE::StringKnobSummary() << endl;
		return 1;
	}

	THREADID t = PIN_SpawnInternalThread(mythread, NULL, 0, NULL);
	if (t!=1)
		cerr << "ERROR internal thread " << t << endl;

	cout << endl << "MAXTHREADS: " << MAXTHREADS << " COMMSIZE: " << COMMSIZE << " PAGESIZE: " << MYPAGESIZE << " INTERVAL: " << INTERVAL << endl << endl;

	if (DOPAGE)
		INS_AddInstrumentFunction(trace_memory_page, 0);

	if (DOCOMM) {
		INS_AddInstrumentFunction(trace_memory_comm, 0);
		for (int i=0; i<100*1000*1000; i++) {
			commmap[i].first = 0;
			commmap[i].second = 0;
		}
	}

	IMG_AddInstrumentFunction(InitMain, 0);
	PIN_AddThreadStartFunction(ThreadStart, 0);
	PIN_AddFiniFunction(Fini, 0);

	PIN_StartProgram();
}


void getStructs(const char* file)
{
	char cmd[1024];
	sprintf(cmd, "readelf -s %s | grep OBJECT | awk '{print strtonum(\"0x\" $2) \" \" strtonum($3) \" \" $8}'", file);
	FILE *p = popen(cmd, "r");
	cout << file << " static variables:" << endl;

	char *line = NULL;
	size_t linecap = 0;
	ssize_t linelen;

	UINT64 addr, size;
	char name[1024];

	while ((linelen = getline(&line, &linecap, p)) > 0) {
		fscanf(p, "%lu %lu %s", &addr, &size, name);

		if (size < exp2(MYPAGESIZE))
			continue;

		struct alloc tmp;

		tmp.loc = "unknown.loc";
		tmp.name = PIN_UndecorateSymbolName(name, UNDECORATION_COMPLETE);
		tmp.addr = addr >> MYPAGESIZE;
		tmp.size = size;
		tmp.tid = 0;

		allocations.push_back(tmp);

		cout << "  " << addr << " " << size << " " << PIN_UndecorateSymbolName(name, UNDECORATION_COMPLETE) << endl;
	}
	pclose(p);
}

