#
import os.path
from libc.string cimport memcpy, memset, strcpy, strlen
from libc.stdlib cimport malloc, free

from .vst_header cimport *
from .logger import NLogger


class VstHost(object):
    """ """

    VST_VERSION = 2400

    def __init__(self, sample_rate, buffer_size, **kwargs):
        self.sample_rate = sample_rate
        self.block_size = buffer_size
        self.bpm = 120.0
        self.sample_position = 0
        #
        cdef VstTimeInfo *c_time_info_ptr = <VstTimeInfo*> malloc(sizeof(VstTimeInfo))
        self._time_info = <long long> c_time_info_ptr
        #
        self.logger = NLogger.init('VstHost', kwargs.get("log_level", 'WARNING'))

    def __del__(self):
        free( <void*> <long long> self._time_info )

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
            res = 0



        elif opcode == AudioMasterOpcodes.audioMasterUpdateDisplay:
            res = 0

        elif opcode == AudioMasterOpcodes.audioMasterBeginEdit:
            res = 0

        elif opcode == AudioMasterOpcodes.audioMasterEndEdit:
            res = 0

        else:
            self.logger.warning( "[ %s ] OPCODE is NOT supported by HOST" % str(opcode) )

        return (res, data)
