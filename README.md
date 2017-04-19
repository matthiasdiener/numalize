# Numalize: Detect memory access patterns of parallel applications

Numalize is a memory tracing tool to detect communication (i.e. accesses to shared memory areas) and page usage of parallel applications that use shared-memory APIs (e.g. OpenMP and Pthreads).
It is based on the Intel Pin Dynamic Binary Instrumentation (DBI) tool (https://software.intel.com/en-us/articles/pintool/). 


## Requirements 
- Intel Pin installation (https://software.intel.com/en-us/articles/pintool/). The ```Makefile``` tries to find your Pin installation in ```/home``` and ```/opt```. You can override the path manually in the top of the ```Makefile```. Note that Pin version 3.x is currently required.

## Usage

Compile numalize:

    $ make

Generate communication pattern:

    $ ./run.sh -c -- ./binary
    
    
Generate page access pattern:

    $ ./run.sh -p -- ./binary
    
## Publication
Numalize is described in:

- Matthias Diener, Eduardo H. M. Cruz, Laércio L. Pilla, Fabrice Dupros, Philippe O. A. Navaux. “Characterizing Communication and Page Usage of Parallel Applications for Thread and Data Mapping.” Performance Evaluation, 2015. http://dx.doi.org/10.1016/j.peva.2015.03.001
