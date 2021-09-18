#
import os
import time
import json
import ctypes
import math
import numpy
import soundfile

from .vst_host import VstHost
from .vst_plugin import VstPlugin
from .logger import NLogger
from .vst_exceptions import VST_ChainWorkException



class VstChainWorker(object):
    """docstring for PluginChain"""

    DEF NORMILIZED_RMS_DB_TO_60ms_ATTACK_200ms_RELEASE = 5.25

    def __init__(self, buffer_size=1024, **kwargs):
        """ """
        self._buffer_size = buffer_size
        #
        self._display_info_after_load = kwargs.get("display_info", False)
        self.logger = kwargs.get("logger", NLogger.init('VstChainWorker', kwargs.get("log_level", 'WARNING')))


    # -------------------------------------------------------------------------


    @NLogger.wrap('DEBUG')
    def _vst_plugin_create(self, vst_host, samplerate, **kwargs):
        """ """
        vst_lib_path = kwargs.get("path", "")
        shell_uid = kwargs.get("shell_uid", -1)
        max_channels = kwargs.get("max_channels", 8)
        parameters = kwargs.get("params", {})

        assert os.path.isfile(vst_lib_path), "%s is not a file!" % vst_lib_path
        assert isinstance(shell_uid, int)
        assert isinstance(max_channels, int) and max_channels > 0 and max_channels < 16
        assert isinstance(parameters, dict)

        plugin = VstPlugin(
            vst_host,
            vst_lib_path,
            samplerate,
            block_size=self._buffer_size,
            max_channels=max_channels,
            self_buffers=True,
            shell_uid=shell_uid,
            logger=self.logger,
            log_level=self.logger.level
        )
        #
        for k,v in parameters.items():
            plugin.parameter_value(
                name=k,
                normalized=v.get("normalized", True),
                value=v.get("value", 0.0),
                fullscale=v.get("fullscale", 1.0),
                l=v.get("l", "dB")
            )

        self.logger.info("LOADED VST PLUGIN: %s " % plugin.name)

        if self._display_info_after_load:
            NLogger.current_level(self.logger, "\n\n%s" % plugin.info())

        return plugin

    @NLogger.wrap('DEBUG')
    def _vst_plugin_chain_create_list(self, json_list, samplerate):
        """ """
        vst_host = VstHost(samplerate, self._buffer_size, logger=self.logger, log_level=self.logger.level)

        chain_list = []
        for k,v in json_list["plugins_list"].items():
            chain_list.append(
                self._vst_plugin_create( vst_host, samplerate, **v )
            )
        return chain_list

    @NLogger.wrap('DEBUG')
    def _vst_plugin_chain_channels_range(self, chain, in_file):
        channels_range = range(in_file.channels)
        #
        for vst_plugin in chain:
            if vst_plugin.output_channels < in_file.channels:
                raise VST_ChainWorkException(
                    "VST [%s] has OUTPUT channels count [%d] less than audio file channels [%d]" % (vst_plugin.name, vst_plugin.output_channels, in_file.channels))
            if vst_plugin.input_channels < in_file.channels:
                raise VST_ChainWorkException(
                    "VST [%s] has INPUT channels count [%d] less than audio file channels [%d]" % (vst_plugin.name, vst_plugin.input_channels, in_file.channels))
        #
        return channels_range


    # -------------------------------------------------------------------------


    @NLogger.wrap('DEBUG')
    def rms_peak_measurment(self, in_filepath):
        # open input audio file
        in_file = soundfile.SoundFile(in_filepath, mode='r', closefd=True)

        peak_max = 0
        meas_rms_float = 0
        block_cnt = 0
        #
        for block in in_file.blocks(blocksize=1024*10, overlap=512*10):
            meas_rms_float += numpy.sqrt(numpy.mean(block**2))
            b_max = numpy.amax(block)
            if b_max > peak_max:
                peak_max = b_max
            block_cnt += 1
        #
        in_file.close()

        meas_rms_float /= block_cnt
        meas_rms_db = (20 * math.log10(meas_rms_float)) + NORMILIZED_RMS_DB_TO_60ms_ATTACK_200ms_RELEASE
        peak_max_db = math.log10(peak_max / 1.0) * 20

        self.logger.info( "Measured for '%s' - [ RMS: %.2f dB, Peak: %.2f dB ]" % (os.path.basename(in_filepath), meas_rms_db, peak_max_db) )
        return (meas_rms_float, meas_rms_db, peak_max, peak_max_db)

    @NLogger.wrap('DEBUG')
    def vst_plugin_chain_process_file(self, chain, in_file, out_file):

        # verify and get range for input/output file channels and plugins channels
        channels_range = self._vst_plugin_chain_channels_range(chain, in_file)

        # allocate channels temporary C buffers memory
        temp_buffer = []
        for ch in channels_range:
            temp_buffer.append( VstHost.allocate_float_buffer(self._buffer_size) )

        # read block -> plugins chain work -> write block
        for block in in_file.blocks(blocksize=self._buffer_size, always_2d=True):
            #
            block_len = len(block)
            block_rl = block.transpose()

            # copy channel data and fill C pointers array
            in_buf_c_p = []
            for ch in channels_range:
                data_ch = block_rl[ch].astype(numpy.float32)
                VstHost.copy_buffer(temp_buffer[ch], data_ch.ctypes.data, block_len)
                in_buf_c_p.append(temp_buffer[ch])

            # VST plugins chain work
            for vst_plugin in chain:
                # vst process
                vst_plugin.process_replacing( in_buf_c_p, vst_plugin.out_buffers, block_len )
                in_buf_c_p = vst_plugin.out_buffers

            # prepare out block data
            out_np_array = []
            for ch in channels_range:
                out_np_array.append( numpy.ctypeslib.as_array( ctypes.cast(chain[-1].out_buffers[ch], ctypes.POINTER(ctypes.c_float)), shape=(block_len, 1) ) )

            # write out block data
            out_file.write(
                numpy.column_stack( tuple(out_np_array[ch] for ch in channels_range) )
            )

        # free channels temporary C buffers memory
        for ch in channels_range:
            VstHost.free_buffer(temp_buffer[ch])

    @NLogger.wrap('DEBUG')
    def procces_file(self, job_file, infilepath, outfilepath):
        """ """
        start = time.time()

        # open json job file
        with open(job_file, "r") as f:
            json_data = json.load(f)
        chain = json_data

        if "normalize" in chain.keys() and chain["normalize"]["enable"]:
            self.logger.info( "Normilize [ ENABLED ]" )

            target_rms_dB = chain["normalize"]["target_rms"]
            error_db = chain["normalize"]["error_db"]

            meas_rms_float, meas_rms_db, peak_max, peak_max_db = self.rms_peak_measurment(infilepath)
            change_db = target_rms_dB - meas_rms_db
            self.logger.info( "Normilize [ COEFFICIENT ]: %.3f dB" % change_db )

            if meas_rms_db < (target_rms_dB - error_db) or meas_rms_db > (target_rms_dB + error_db):
                try:
                    limiter_settings = chain["plugins_list"]["FabFilter Pro-L 2 (0)"]["params"]
                    limiter_settings["Bypass"]["value"] = 0.0
                    if change_db > 0:
                        limiter_settings["Gain"]["value"] = change_db
                        limiter_settings["Gain"]["fullscale"] = 30.0
                        limiter_settings["Gain"]["normalized"] = False
                    else:
                        limiter_settings["Output Level"]["value"] = change_db
                        limiter_settings["Output Level"]["fullscale"] = -30.0
                        limiter_settings["Output Level"]["normalized"] = False
                except KeyError:
                    self.logger.warning("[ FabFilter Pro-L 2 ] as the first plugin in chain are not found! Normilize are [ DISABLED ]")

        self.logger.info("[ VST CHAIN START.... ] - %s " % os.path.basename(infilepath))

        # open input audio file
        in_file = soundfile.SoundFile(infilepath, mode='r', closefd=True)

        # create vst plugins chain for current job
        _plugin_chain = self._vst_plugin_chain_create_list(chain, in_file.samplerate)

        # create output audio file
        out_file = soundfile.SoundFile(outfilepath, mode='w', samplerate=in_file.samplerate, channels=in_file.channels, subtype=in_file.subtype, closefd=True)

        # process all plugins in job
        self.vst_plugin_chain_process_file(_plugin_chain, in_file, out_file)

        # close audiofiles
        in_file.close()
        out_file.close()
        end_time = time.time()-start
        self.logger.info("[ VST CHAIN COMPLITE ] - from %s - saved to - %s " % (os.path.basename(infilepath), os.path.basename(outfilepath)))
        self.logger.info("[ END ] - Elapsed time: [ %.3f | %.3f ]" % (end_time, end_time/60))
