#!/usr/bin/env python3
"""mayhem/reap.py <cmd> [args...] — run <cmd> as a child subreaper and return its exit code.

pttbbs' Go service tests (svcctl's TestMainArgs, TestRestart*) start a detached fake daemon,
SIGTERM it and then poll kill(pid, 0) until it is gone. The daemon is re-parented to the nearest
subreaper, normally PID 1; in a container whose PID 1 never calls wait() (`sleep infinity`,
`docker exec` sessions) the daemon stays a zombie, kill() keeps succeeding and the test fails
after 5 s. Making this process the subreaper, and reaping every child it inherits, gives the
tests the init they assume, whatever PID 1 is.
"""
import ctypes
import os
import sys

PR_SET_CHILD_SUBREAPER = 36

ctypes.CDLL(None, use_errno=True).prctl(PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0)
pid = os.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
while True:
    p, status = os.wait()
    if p == pid:
        sys.exit(os.waitstatus_to_exitcode(status))
