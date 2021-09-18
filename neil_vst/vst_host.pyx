#
import ctypes
import numpy

from libc.string cimport memcpy, memset, strcpy, strlen
from libc.stdlib cimport malloc, free

from .vst_header cimport *
from .logger import NLogger
from .vst_exceptions import VST_HostChainException


class VstHost(object):
    """ """

    VST_VERSION = 2400

    def __init__(self, sample_rate, block_size=1024, **kwargs):
        self.sample_rate = sample_rate
        self.block_size = block_size
        self.bpm = 120.0
        self.sample_position = 0
        #
        cdef VstTimeInfo *c_time_info_ptr = <VstTimeInfo*> malloc(sizeof(VstTimeInfo))
        self._time_info = <long long> c_time_info_ptr
        #
        self._shell_uid = kwargs.get("shell_uid", -1)
        #
        self.gui_callback = kwargs.get("gui_callback", None)
        #
        self.logger = kwargs.get("logger", NLogger.init('VstHost', kwargs.get("log_level", 'WARNING')))
        #
        self._process_chain_stop = False

    def __del__(self):
        free( <void*> <long long> self._time_info )

    # -------------------------------------------------------------------------

    @property
    def shell_uid(self):
        return self._shell_uid

    @shell_uid.setter
    def shell_uid(self, value):
        self._shell_uid = value

    # -------------------------------------------------------------------------

    @staticmethod
    def allocate_float_buffer(int size) -> int:
        cdef float *ptr = <float*> malloc(size * sizeof(float))
        memset(<void*> ptr, 0, size * sizeof(float))
        return <long long> ptr

    @staticmethod
    def allocate_double_buffer(int size) -> int:
        cdef double *ptr = <double*> malloc(size * sizeof(double))
        return <long long> ptr

    @staticmethod
    def copy_buffer(to_pointer, from_pointer, size):
        memcpy(<void*> <long long> to_pointer, <void*> <long long> from_pointer, size * sizeof(float))

    @staticmethod
    def free_buffer(pointer):
        free(<void*> <long long> pointer)


    # -------------------------------------------------------------------------

    @NLogger.wrap('DEBUG')
    def process_chain_start(self, filename, channels, plugins_chain, in_blocks_np, out_write_cb, frames=-1, start=0, stop=None):
        """
        channels: int
            The number of audio channels
        plugins_chain: list
            The list of VST plugins, all plugins must be successfuly loaded
        in_blocks_np: numpy.ndarray
            Blocks of audio data.
        out_write_cb: output data callback function
            Called this function after end of each audio block in in_blocks_np,
            numpy.ndarray data return
        frames : int, optional
            The number of frames to read. If `frames` is negative, the whole
            rest of the file is read.  Not allowed if `stop` is given.
        start : int, optional
            Where to start reading.  A negative value counts from the end.
        stop : int, optional
            The index after the last frame to be read.  A negative value
            counts from the end.  Not allowed if `frames` is given.
        """
        # self._process_chain_active = True
        self._process_chain_stop = False

        # verify and get range for input/output file channels and plugins channels
        channels_range = range(channels)
        #
        for vst_plugin in plugins_chain:
            if vst_plugin.output_channels < channels:
                raise VST_HostChainException(
                    "VST [%s] has OUTPUT channels count [%d] less than audio file channels [%d]" % (vst_plugin.name, vst_plugin.output_channels, channels))
            if vst_plugin.input_channels < channels:
                raise VST_HostChainException(
                    "VST [%s] has INPUT channels count [%d] less than audio file channels [%d]" % (vst_plugin.name, vst_plugin.input_channels, channels))

        # allocate channels temporary C buffers memory
        temp_buffer = []
        for ch in channels_range:
            temp_buffer.append( self.allocate_float_buffer(self.block_size) )

        # read block -> plugins chain work -> write block
        for block in in_blocks_np(filename, blocksize=self.block_size, frames=frames, start=start, stop=stop, always_2d=True):
            #
            block_len = len(block)
            block_rl = block.transpose()

            # copy channel data and fill C pointers array
            in_buf_c_p = []
            for ch in channels_range:
                data_ch = block_rl[ch].astype(numpy.float32)
                self.copy_buffer(temp_buffer[ch], data_ch.ctypes.data, block_len)
                in_buf_c_p.append(temp_buffer[ch])

            # VST plugins chain work
            for vst_plugin in plugins_chain:
                # vst process
                vst_plugin.process_replacing( in_buf_c_p, vst_plugin.out_buffers, block_len )
                in_buf_c_p = vst_plugin.out_buffers

            # prepare out block data
            out_np_array = []
            for ch in channels_range:
                out_np_array.append( numpy.ctypeslib.as_array( ctypes.cast(in_buf_c_p[ch], ctypes.POINTER(ctypes.c_float)), shape=(block_len, 1) ) )

            # write out block data
            out_write_cb(
                numpy.column_stack( tuple(out_np_array[ch] for ch in channels_range) )
            )

            if self._process_chain_stop:
                # print("process_chain [ TERMINATE ]")
                break

        # free channels temporary C buffers memory
        for ch in channels_range:
            self.free_buffer(temp_buffer[ch])

        # self._process_chain_active = False
        # print("process_chain [ EXIT ]")

    @NLogger.wrap('DEBUG')
    def process_chain_stop(self):
        self._process_chain_stop = True


    # -------------------------------------------------------------------------


    @NLogger.wrap('DEBUG')
    def host_callback(self, plugin, opcode, index, value, ptr, opt):
        """ """
        #
        cdef AEffect* c_plugin_pointer = <AEffect*> <long long> plugin
        #
        cdef VstTimeInfo *c_time_info_ptr
        cdef VstInt32 flags = 0
        #
        res = -1
        data = None
        #
        if opcode == AudioMasterOpcodes.audioMasterAutomate:
            c_plugin_pointer.setParameter(c_plugin_pointer, index, opt);
            res = 0

        elif opcode == AudioMasterOpcodes.audioMasterVersion:
            res = VstHost.VST_VERSION

        elif opcode == AudioMasterOpcodes.audioMasterCurrentId:
            if self._shell_uid != -1:
                res = self._shell_uid
            else:
                res = c_plugin_pointer.uniqueID

        elif opcode == AudioMasterOpcodes.audioMasterGetBlockSize:
            res = self.block_size

        elif opcode == AudioMasterOpcodes.audioMasterGetSampleRate:
            res = self.sample_rate

        elif opcode == AudioMasterOpcodes.audioMasterGetProductString:
            res = 0
            data = b"Neil-VST"

        elif opcode == AudioMasterOpcodes.audioMasterWantMidi:
            res = -1

        elif opcode == AudioMasterOpcodes.audioMasterGetTime:
            c_time_info_ptr = <VstTimeInfo*> <long long> self._time_info
            c_time_info_ptr.samplePos = self.sample_position
            c_time_info_ptr.sampleRate = self.sample_rate
            c_time_info_ptr.flags |= kVstTransportPlaying
            res = <long long> <VstIntPtr> c_time_info_ptr

        elif opcode == AudioMasterOpcodes.audioMasterGetCurrentProcessLevel:
            # res = VstProcessLevels.kVstProcessLevelUnknown
            res = VstProcessLevels.kVstProcessLevelOffline

        elif opcode == AudioMasterOpcodes.audioMasterCanDo:
            str_ptr = str(ptr, "utf-8")
            if 'offline' in str_ptr:
                res = 0

        elif opcode == AudioMasterOpcodes.audioMasterPinConnected:
            res = 0

        elif opcode == AudioMasterOpcodes.audioMasterIOChanged:
            res = 0

        elif opcode == AudioMasterOpcodes.audioMasterGetVendorString:
            res = 0
            data = b"Neil Lab"

        elif opcode == AudioMasterOpcodes.audioMasterGetVendorVersion:
            res = 1

        elif opcode == AudioMasterOpcodes.audioMasterSizeWindow:
            if self.gui_callback:
                self.gui_callback("audioMasterSizeWindow", plugin, index, value, ptr, opt)
            res = 0

        elif opcode == AudioMasterOpcodes.audioMasterUpdateDisplay:
            if self.gui_callback:
                self.gui_callback("audioMasterUpdateDisplay", plugin, index, value, ptr, opt)
            res = 0

        elif opcode == AudioMasterOpcodes.audioMasterBeginEdit:
            res = 0

        elif opcode == AudioMasterOpcodes.audioMasterEndEdit:
            res = 0

        else:
            self.logger.warning( "[ %s ] OPCODE is NOT supported by HOST" % str(opcode) )

        return (res, data)
