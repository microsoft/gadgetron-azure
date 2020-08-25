import os
import sys
import pyinotify
import re
import getopt
from prometheus_client import start_http_server, Counter

wm = pyinotify.WatchManager()
mask = pyinotify.IN_MODIFY

class EventHandler (pyinotify.ProcessEvent):

    def __init__(self, file_path, *args, **kwargs):
        super(EventHandler, self).__init__(*args, **kwargs)
        start_http_server(8080)
        self.file_path = file_path
        self._last_position = 0
        self._new_recon_pat = re.compile("[^\[]*\[[a-zA-Z\.]+:[0-9]+\] Connection state: \[STREAM\]")
        self._finish_recon_pat = re.compile("[^\[]*\[[a-zA-Z\.]+:[0-9]+\] Connection state: \[FINISHED\]")
        self._new_recon_counter = Counter('gadgetron_reconstruction_start_total', 'Gadgetron reconstructions started')
        self._finish_recon_counter = Counter('gadgetron_reconstruction_finish_total', 'Gadgetron reconstructions finished')

    def process_IN_MODIFY(self, event):
        if self._last_position > os.path.getsize(self.file_path):
            self._last_position = 0
        with open(self.file_path) as f:
            f.seek(self._last_position)
            loglines = f.readlines()
            self._last_position = f.tell()
            for l in loglines:
                if self._new_recon_pat.match(l):
                    self._new_recon_counter.inc()
                elif self._finish_recon_pat.match(l):
                    self._finish_recon_counter.inc()

def main(argv):
  logfile = ''
  try:
    opts, args = getopt.getopt(argv,"hl:",["logfile="])
  except getopt.GetoptError:
    print('log-monitor.py -l <logfile>')
    sys.exit(2)

  for opt, arg in opts:
    if opt == '-h':
      print('log-monitor.py -l <logfile>')
      sys.exit()
    elif opt in ("-l", "--logfile"):
      logfile = arg

  if len(logfile) == 0:
    print('log-monitor.py -l <logfile>')
    sys.exit(2)

  if not os.path.exists(logfile):
    os.mknod(logfile)

  handler = EventHandler(logfile)
  notifier = pyinotify.Notifier(wm, handler)

  wm.add_watch(handler.file_path, mask)        
  notifier.loop()

if __name__ == "__main__":
  main(sys.argv[1:])