# py-neil-vst

Cython-based simple VST 2.4 Host and VST Plugins wrapper. Fast work and clean python object-oriented interface, minimum memory required for the one VST HOST instance.

- Supported platforms: **Windows 64bit**
- Supported python versions: **3.7**, **3.8**, **3.9**
- Supported VST Plugins: only **64-bit/VST2**

Create VST host and the one VST plugin (XILS DeeS) example:
```python
from neil_vst import VstHost, VstPlugin
# create VST host
vst_host = VstHost(samplerate=44100, buffer_size=1024, log_level="DEBUG")
# create VST plugin effect
plugin = VstPlugin(
    host=vst_host,
    vst_path_lib="C:/Program Files/Common Files/VST2/XILS DeeS.dll",
    sample_rate=44100,
    block_size=1024,
    max_channels=4,
    self_buffers=True,
    log_level="DEBUG",
)

print( plugin.info() )
```

Process stereo audio file with Raum VST plugin:
```python
import numpy
from soundfile import SoundFile
from neil_vst import VstHost, VstPlugin

# open input audio file
in_file = SoundFile(infilepath, mode='r', closefd=True)
# create output audio file
out_file = SoundFile(
    outfilepath,
    mode='w',
    samplerate=in_file.samplerate,
    channels=in_file.channels,
    subtype=in_file.subtype,
    closefd=True
)
# sample buffer size
buffer_size = 1024
# create VST host
vst_host = VstHost(samplerate=in_file.samplerate, buffer_size=buffer_size, log_level="DEBUG")
# create VST plugin effect
plugin = VstPlugin(
    host=vst_host,
    vst_path_lib="C:/Program Files/Common Files/VST2/Raum.dll",
    sample_rate=in_file.samplerate,
    block_size=buffer_size,
    max_channels=8,
    self_buffers=True,
    log_level="DEBUG",
)
# process stereo audio file
for block in in_file.blocks(blocksize=self._buffer_size, always_2d=True):
    # prepare buffer from numpy array
    block_rl = block.transpose()
    buf_in = [
        block_rl[0].astype(numpy.float32).ctypes.data,
        block_rl[1].astype(numpy.float32).ctypes.data ]
    # VST process replasing
    plugin.process_replacing( buf_in, plugin.out_buffers, len(block) )
    # get back to numpy array for save to output audio file
    out_left = numpy.ctypeslib.as_array(
        ctypes.cast(plugin.out_buffers[0], ctypes.POINTER(ctypes.c_float)), shape=(len(block),)
    )
    out_right = numpy.ctypeslib.as_array(
        ctypes.cast(plugin.out_buffers[1], ctypes.POINTER(ctypes.c_float)), shape=(len(block),)
    )
    # write out data to output audio file
    out_file.write( [out_left, out_right] )
```

Open VST plugin GUI with PyQt5 QWidget with callback example:
```python
import sys
import logging
from PyQt5 import QtWidgets
from neil_vst import VstHost, VstPlugin

class VSTPluginWindowExample(QtWidgets.QWidget):
    def __init__(self, plugin, parent=None):
        super(VSTPluginWindowExample, self).__init__(parent)
        # set self window name
        self.setWindowTitle(plugin.name)
        # set self size corresponding to plugin size
        rect = plugin.edit_get_rect()
        self.resize(rect["right"], rect["bottom"])
        # open plugin GUI to self
        plugin.edit_open(int(self.winId()))
        # self show
        self.show()

if __name__ == '__main__':
    app = QtWidgets.QApplication(sys.argv)
    vst_host = VstHost(44100, log_level=logging.DEBUG)
    plugin = VstPlugin(vst_host, "C:/Program Files/Common Files/VST2/TDR VOS SlickEQ.dll", log_level=logging.DEBUG)
    plugin_window = VSTPluginWindowExample(plugin)
    sys.exit(app.exec_())
```

CLI util example:
```console
>>> neil_vst_chain -h

usage: neil_vst_chain [-h] [-f FOLDER] [-j JOB] [-o OUTPUT] [-b BUFFERSIZE] [-v] [-i]

optional arguments:
  -h, --help            show this help message and exit
  -f FOLDER, --folder FOLDER
                        folder with input audio files (default: .)
  -j JOB, --job JOB     JSON job file
  -o OUTPUT, --output OUTPUT
                        output folder for audio files (default: ./out)
  -b BUFFERSIZE, --buffersize BUFFERSIZE
                        buffer size in bytes [1024...65536] (default: 8096)
  -v, --verbose         verbose logging (default: False)
  -i, --info            show all parameters info for loaded VST (default: False)
```

Process all files in selected folder from CLI example:
```console
>>> neil_vst_chain -f in_folder -j job_file.json -o out_folder -b 16192
or
>>> neil_vst_chain --folder in_folder --job job_file.json --output out_folder --buffersize 16192

```
