#
import os
import re

from libc.string cimport memcpy, strcpy, strlen
from libc.stdlib cimport malloc, free

from .vst_header cimport *
from .vst_host import VstHost
from .vst_exceptions import VSTPluginLoadException
from .logger import NLogger


DEF VST_MAGIC_NUM = int.from_bytes(b'VstP', 'big') # 1450406992

_init_host = None


class VstPlugin(object):
    """ """

    _host_binds = {}

    def __init__(self, host, vst_path_lib, sample_rate=44100, block_size=1024, max_channels=16, self_buffers=False, **kwargs):
        # set temp host for vst lib load procedure
        global _init_host
        _init_host = host

        # get unique ID for shell dll (like Waves) and save it to host
        _init_host.shell_uid = kwargs.get("shell_uid", -1)

        # load VST and create self instance
        self._path_to_lib = vst_path_lib
        self._instance = self._load_vst_dll(self._path_to_lib)

        # save host to bind list
        VstPlugin._host_binds.pop(self.unique_id, None)
        VstPlugin._host_binds[self.unique_id] = host

        # reset temp host, vst lib load procedure complite
        _init_host = None

        # create self IO buffers
        if self_buffers:
            self._in_out_self_buffers = True
            self._create_buffers(block_size)
        else:
            self._in_out_self_buffers = False

        # pointers for convert input and output data types to C <float**> and <double*> types
        # one pointer for one channel data array
        cdef void* input_pointers = malloc(max_channels * sizeof(double))
        cdef void* output_pointers = malloc(max_channels * sizeof(double))
        self._c_in_channels_buff = <long long> input_pointers
        self._c_out_channels_buff = <long long> output_pointers

        # buffer for returns from "parameter_name", "parameter_label" etc.
        cdef void* _c_char_buff = malloc( 1024 * sizeof(char) )
        self._c_string_buff = <long long> _c_char_buff
        # buffer for returns from "edit_get_rect"
        cdef int* e_rect = <int*> <long long> malloc(16)
        self._c_rect_buff = <long long> e_rect

        # start VST plugin
        self._dispatch_to_c_plugin(AEffectOpcodes.effOpen, 0, 0, <long long> NULL, 0.0)
        self._dispatch_to_c_plugin(AEffectOpcodes.effSetSampleRate, 0, 0, <long long> NULL, float(sample_rate))
        self._dispatch_to_c_plugin(AEffectOpcodes.effSetBlockSize, 0, block_size, <long long> NULL, 0.0)

        # init self logger
        self.logger = kwargs.get("logger", NLogger.init('VstPlugin', kwargs.get("log_level", 'WARNING')))

    def __del__(self):
        """ Free all allocated memory buffers """
        # free allocated buffers
        if self._in_out_self_buffers:
            self._free_buffers()
        # close plugin
        self._dispatch_to_c_plugin(AEffectOpcodes.effClose, 0, 0, <long long> NULL, 0.0)
        # delete plugin from bind list
        VstPlugin._host_binds.pop(self.unique_id, None)
        # free other buffers
        free( <void*> <long long> self._c_string_buff )
        free( <void*> <long long> self._c_rect_buff )
        free( <void*> <long long> self._c_in_channels_buff )
        free( <void*> <long long> self._c_out_channels_buff )

    # -------------------------------------------------------------------------

    @property
    def instance(self):
        return self._instance

    @property
    def unique_id(self):
        return (<AEffect*> <long long> self._instance).uniqueID

    @property
    def shell_unique_id(self):
        return self._shell_unique_id

    @property
    def version(self):
        return (<AEffect*> <long long> self._instance).version

    @property
    def name(self):
        cdef long long out_buf = <long long> self._c_string_buff
        self._dispatch_to_c_plugin(AEffectXOpcodes.effGetEffectName, 0, 0, out_buf, 0.0)
        return str( <char*> out_buf, "utf-8" )

    @property
    def vendor(self):
        cdef long long out_buf = <long long> self._c_string_buff
        self._dispatch_to_c_plugin(AEffectXOpcodes.effGetVendorString, 0, 0, out_buf, 0.0)
        return str( <char*> out_buf, "utf-8" )

    @property
    def product(self):
        cdef long long out_buf = <long long> self._c_string_buff
        self._dispatch_to_c_plugin(AEffectXOpcodes.effGetProductString, 0, 0, out_buf, 0.0)
        return str( <char*> out_buf, "utf-8" )

    @property
    def flags(self):
        return (<AEffect*> <long long> self._instance).flags

    @property
    def is_synth(self):
        return bool( self.flags & VstAEffectFlags.effFlagsIsSynth )

    @property
    def allows_double_precision(self):
        return bool( self.flags & VstAEffectFlags.effFlagsCanDoubleReplacing )

    @property
    def input_channels(self):
        return (<AEffect*> <long long> self._instance).numInputs

    @property
    def output_channels(self):
        return (<AEffect*> <long long> self._instance).numOutputs

    @property
    def programs_num(self):
        return (<AEffect*> <long long> self._instance).numPrograms

    @property
    def parameters_num(self):
        return (<AEffect*> <long long> self._instance).numParams

    @property
    def parameters_indexes_dict(self):
        params = {}
        for p in range( self.parameters_num ):
            params[self.parameter_name(p)] = p
        return params

    @property
    def in_buffers(self):
        if self._in_out_self_buffers:
            return self._in_buffer_ch

    @property
    def out_buffers(self):
        if self._in_out_self_buffers:
            return self._out_buffer_ch

    @property
    def path_to_lib(self):
        return self._path_to_lib

    # -------------------------------------------------------------------------

    def _create_buffers(self, block_size):
        self._in_buffer_ch = []
        for channel in range(self.input_channels):
            self._in_buffer_ch.append( VstHost.allocate_float_buffer(block_size) )
        self._out_buffer_ch = []
        for channel in range(self.output_channels):
            self._out_buffer_ch.append ( VstHost.allocate_float_buffer(block_size) )

    def _free_buffers(self):
        for channel in range(self.input_channels):
            free( <void*> <long long> self._in_buffer_ch[channel] )
        for channel in range(self.output_channels):
            free( <void*> <long long> self._out_buffer_ch[channel] )

    def _load_vst_dll(self, path_to_vst_lib):
        """ """
        if not os.path.isfile(path_to_vst_lib):
            raise VSTPluginLoadException("VST dll file - [%s] not found!" % path_to_vst_lib)

        # https://docs.microsoft.com/en-us/windows/win32/api/libloaderapi/nf-libloaderapi-loadlibraryexa
        cdef HMODULE handle = LoadLibraryA(bytes(path_to_vst_lib, "utf-8"))
        if handle is NULL:
            raise VSTPluginLoadException("null pointer when loading a DLL. Error code = " + str(GetLastError()))
        #
        cdef VSTPluginMainPtr entry_function = <VSTPluginMainPtr> GetProcAddress(handle, "VSTPluginMain");
        if entry_function is NULL:
            raise VSTPluginLoadException("null pointer when obtaining an address of the entry function. Error code = " + str(GetLastError()))
        #
        cdef AEffect *_instance = entry_function(_c_host_callback)
        #
        if <long long> _instance == 0:
            raise VSTPluginLoadException("Load the VST dll are failed!")
        if VST_MAGIC_NUM != _instance.magic:
            raise VSTPluginLoadException('VST "magic number" is wrong!')

        return <long long> _instance

    def _dispatch_to_c_plugin(self, opcode, index, value, long long ptr, float opt):
        cdef AEffect* _instance = <AEffect*> <long long> self._instance
        cdef void *cast_parameter_pointer = <void*> ptr
        assert ( index >= 0 and index < _instance.numParams ), \
            'Parameter [%s] index is out of range - [0..%s]' % (str(index), _instance.numParams)
        return _instance.dispatcher(_instance, opcode, index, value, cast_parameter_pointer, opt)

    @NLogger.wrap('DEBUG')
    def _set_not_normilized_value(self, index, value, fullscale, steps, l):

        #
        cdef AEffect* _instance = <AEffect*> <long long> self._instance
        #
        temp = value
        if value < 0:
            temp = -fullscale + value
        #
        write_val = abs(temp) / abs(fullscale)
        #
        default_val = _instance.getParameter(_instance, index)
        #
        _instance.setParameter(_instance, index, write_val)
        #
        def _read_display_value(index):
            try:
                return float( re.findall(r"[-+]?\d*\.\d+|\d+", self.parameter_display(index))[0] )
            except Exception as e:
                self.logger.error((str(e), str(self.name), self.parameter_name(index), self.parameter_display(index)))
                return 0

        read_val = _read_display_value(index)


        if value == read_val:
            return True

        self.logger.debug("Parameter scale are is not linear type, try set correct value...")

        fullscale *= steps
        #
        step = 0
        val_min = 0
        val_max = fullscale
        replicate_result_cnt = 0
        #
        while step < steps:
            #
            center = val_min + ( (val_max-val_min) / 2 )
            # set parameter [ normalized to 0,0...1,0 ]
            _instance.setParameter(_instance, index, center / fullscale)
            # read real setted value
            r_val = _read_display_value(index)
            # dimension multiplyer
            # if r_val[1][0].lower() != l[0].lower():
            #     r_val = 1000 * float( r_val[0] )
            # else:
            #     r_val = float( r_val[0] )
            # if read value equal to reqested, or identical values read more then 10 times
            if r_val == value or replicate_result_cnt > 10:
                # self.logger.debug("Setted OK, step: %s, read_val: %s" % (step, r_val))
                return True
            elif r_val < value:
                if val_min == center:
                    replicate_result_cnt += 1
                val_min = center
            elif r_val > value:
                if val_max == center:
                    replicate_result_cnt += 1
                val_max = center
            # decrement step
            step += 1
            #
        self.logger.warning("Parameter set procedure invalid, value not changed")
        return False

    # -------------------------------------------------------------------------

    def info(self):
        s = "name: %s\nvendor: %s\nproduct: %s\nunique plugin ID: %s\n" \
            "version: %s\nis synth: %s\ndouble precision (64 bit): %s\n" \
            "input channels: %s\noutput channels: %s\nprograms num: %s\n" \
            "parameters num: %s\n" % (
            self.name,
            self.vendor,
            self.product,
            self.unique_id,
            self.version,
            self.is_synth,
            self.allows_double_precision,
            self.input_channels,
            self.output_channels,
            self.programs_num,
            self.parameters_num
        )
        for k,v in self.parameters_indexes_dict.items():
            s += "%s - %s - %f; [display] - %s %s\n" % (
                v,
                k,
                self.parameter_value(index=v),
                self.parameter_display(v),
                self.parameter_label(v)
            )
        return s

    @NLogger.wrap('DEBUG')
    def parameter_value(self, index=-1, name=None, normalized=True, value=None, fullscale=1.0, steps=100000, l='dB'):
        #
        cdef AEffect* _instance = <AEffect*> <long long> self._instance
        #
        assert name or index >= 0, "not provided parameter name or index"
        if index == -1:
            index = self.parameters_indexes_dict[name]
        #
        if value is None:
            return _instance.getParameter(_instance, index)
        elif not normalized:
            return self._set_not_normilized_value(index, value, fullscale, steps, l)
        else:
            return _instance.setParameter(_instance, index, value)

    def parameter_name(self, index=-1):
        cdef long long out_buf = <long long> self._c_string_buff
        res = self._dispatch_to_c_plugin ( AEffectOpcodes.effGetParamName, index, 0, out_buf, 0.0 )
        return str(<char*> out_buf, "utf-8")

    def parameter_display(self, index):
        cdef long long out_buf = <long long> self._c_string_buff
        self._dispatch_to_c_plugin ( AEffectOpcodes.effGetParamDisplay, index, 0, out_buf, 0.0 )
        return str( <char*> out_buf, "utf-8" )

    def parameter_label(self, index):
        cdef long long out_buf = <long long> self._c_string_buff
        self._dispatch_to_c_plugin (AEffectOpcodes.effGetParamLabel, index, 0, out_buf, 0.0)
        return str( <char*> out_buf, "utf-8" )

    def parameter_properties(self, index):
        cdef long long out_buf = <long long> self._c_string_buff
        self._dispatch_to_c_plugin ( AEffectXOpcodes.effGetParameterProperties, index, 0, out_buf, 0.0 )
        return str( <char*> out_buf, "utf-8" )

    # -------------------------------------------------------------------------

    def process_replacing(self, input_channels, output_channels, block_len: int):
        """ """
        # extend buffer channels if needed (for example: MONO OUT -> VST PLUGIN STEREO IN)
        if self.input_channels > len(input_channels):
            for ch in range(self.input_channels - len(input_channels)):
                p = input_channels[ch]
                input_channels.append(p)
        # get the plugin C pointer
        cdef AEffect* _instance = <AEffect*> <long long> self._instance
        # create channel data C pointers arrays
        cdef float** input_pointers = <float**> <long long> self._c_in_channels_buff
        cdef float** output_pointers = <float**> <long long> self._c_out_channels_buff
        # input
        for index in range(self.input_channels):
            tmp = <long long> input_channels[index]
            input_pointers[index] = <float*> tmp
        # output
        for index in range(self.output_channels):
            tmp = <long long> output_channels[index]
            output_pointers[index] = <float*> tmp
        # call the VST dll
        _instance.processReplacing(_instance, input_pointers, output_pointers, block_len)

    def process_double_replacing(self, input_channels, output_channels, block_len: int):
        """ """
        assert self.allows_double_precision(), 'Plugin does not support the double precision.'
        # extend buffer channels if needed (for example: MONO OUT -> VST PLUGIN STEREO IN)
        if self.input_channels > len(input_channels):
            for ch in range(self.input_channels - len(input_channels)):
                p = input_channels[ch]
                input_channels.append(p)
        # get the plugin C pointer
        cdef AEffect* _instance = <AEffect*> <long long> self._instance
        # create channel data C pointers arrays
        cdef double** input_pointers = <double**> <long long> self._c_in_channels_buff
        cdef double** output_pointers = <double**> <long long> self._c_out_channels_buff
        # input
        for index, pointer in enumerate(self.input_channels):
            tmp = <long long> pointer
            input_pointers[index] = <double*> tmp
        # output
        for index, pointer in enumerate(self.output_channels):
            tmp = <long long> pointer
            output_pointers[index] = <double*> tmp
        # call the VST dll
        _instance.processDoubleReplacing(_instance, input_pointers, output_pointers, block_len)

    # -------------------------------------------------------------------------

    def edit_get_rect(self):
        cdef int* e_rect = <int*> <long long> self._c_rect_buff
        self._dispatch_to_c_plugin(AEffectOpcodes.effEditGetRect, 0, 0, <long long> (&e_rect), 0.0)
        py_rect = { "top":(<ERect*>e_rect).top, "left": (<ERect*>e_rect).left, "bottom": (<ERect*>e_rect).bottom, "right": (<ERect*>e_rect).right }
        self.logger.debug("EDIT GET RECT: %s" % py_rect)
        return py_rect

    def edit_open(self, window_pointer, gui_callback=None):
        self.logger.debug("EDIT OPEN...")
        host = VstPlugin._host_binds[ self.unique_id ]
        host.gui_callback = gui_callback
        self._dispatch_to_c_plugin(AEffectOpcodes.effEditOpen, 0, 0, <long long> window_pointer, 0.0)

    def edit_close(self, window_pointer):
        self.logger.debug("EDIT CLOSE...")
        host = VstPlugin._host_binds[ self.unique_id ]
        host.gui_callback = None
        self._dispatch_to_c_plugin(AEffectOpcodes.effEditClose, 0, 0, <long long> NULL, 0.0)


# -----------------------------------------------------------------------------


cdef VstIntPtr _c_host_callback(AEffect* plugin, VstInt32 opcode, VstInt32 index, VstIntPtr value, void* ptr, float opt) with gil :
    """ C-level entry for accessing host through sending opcodes """
    global _init_host
    plugin_p = <long long> plugin

    # print("_c_host_callback 0", plugin_p, "opcode: %s" % opcode, "index: %s" % index, "value: %s" % value, <long long> ptr, opt)

    if plugin_p != 0 and (<AEffect*> plugin_p).uniqueID in VstPlugin._host_binds.keys():
        host = VstPlugin._host_binds[ (<AEffect*> plugin_p).uniqueID ]
    else:
        host = _init_host

    if <long long> ptr != 0:
        ptr_data = bytes(strlen(<char*> ptr))
        strcpy(<char*> ptr_data, <char*> ptr)
    else:
        ptr_data = <long long> ptr

    # Call python registered callback
    result, data = VstHost.host_callback(host, plugin_p, opcode, index, value, ptr_data, opt)

    if data is not None and isinstance(data, bytes):
        memcpy(<void*> ptr, <void*> data, len(data))

    # print("_c_host_callback res: ", result, data)
    return <VstIntPtr> result
