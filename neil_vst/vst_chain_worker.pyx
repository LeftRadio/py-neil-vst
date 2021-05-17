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


class VstChainWorker(object):
    """docstring for PluginChain"""

    DEF NORMILIZED_RMS_DB_TO_60ms_ATTACK_200ms_RELEASE = 5.25

    def __init__(self, buffer_size=1024, **kwargs):
        """ """
        self._buffer_size = buffer_size
        self.logger = NLogger.init('VstChainWorker', kwargs.get("log_level", 'WARNING'))


    # -------------------------------------------------------------------------


    @NLogger.wrap('DEBUG')
    def _vst_plugin_create(self, vst_host, samplerate, **kwargs):
        """ """
        vst_lib_path = kwargs.get("path", "")
        shell_uid = kwargs.get("shell_uid", -1)
        max_channels = kwargs.get("max_channels", 8)
        parameters = kwargs.get("params", {})

        assert os.path.isfile(vst_lib_path)
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
        self.logger.debug("\n\n%s" % plugin.info())

        return plugin

    @NLogger.wrap('DEBUG')
    def _vst_plugin_chain_create_list(self, json_list, samplerate):
        """ """
        vst_host = VstHost(samplerate, self._buffer_size, log_level=self.logger.level)

        chain_list = []
        for k,v in json_list["plugins_list"].items():
            chain_list.append(
                self._vst_plugin_create( vst_host, samplerate, **v )
            )
        return chain_list

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
        self.logger.info( "RMS measured for '%s': [%s], %.3f dB" % (in_filepath, meas_rms_float, meas_rms_db) )

        peak_max_db = math.log10(1.0 / peak_max) * 20
        self.logger.info( "Peak maximum for '%s': [%s], -%.3f dB" % (in_filepath, peak_max, peak_max_db) )

        return (meas_rms_float, meas_rms_db, peak_max, peak_max_db)

    @NLogger.wrap('DEBUG')
    def rms_normilize(self, in_filepath, target_rms_dB=None, error_db=0.0, peak_limit=False):
        #
        assert os.path.isfile(in_filepath)
        assert target_rms_dB is not None and target_rms_dB <= 0
        assert error_db >= 0
        #
        self.logger.info( "RMS normilize for '%s', target level: %.3f db" % (in_filepath, target_rms_dB) )

        meas_rms_float, meas_rms_db, peak_max, peak_max_db = self.rms_peak_measurment(in_filepath)

        if meas_rms_db > (target_rms_dB - error_db) and meas_rms_db < (target_rms_dB + error_db):
            self.logger.info("Normilize not needed, level is %.3f dB" % meas_rms_db)
            return (0.0, 0.0)

        change_in_dB = target_rms_dB - meas_rms_db

        if peak_limit and change_in_dB > peak_max_db:
            change_in_dB = peak_max_db - 0.5
            self.logger.warning("Peak limit, new normilize level is -%.3f dB" % (meas_rms_db+change_in_dB))

        float_coeff = math.pow( 10, change_in_dB / 20 )
        self.logger.info( "Coeff: [%s], -%.3f dB" % (float_coeff, change_in_dB) )

        self.logger.info("Start normilizing...")

        # Normilize processing audio file
        with soundfile.SoundFile(in_filepath, 'r+') as f:
            while f.tell() < f.frames:
                pos = f.tell()
                data = f.read(1024*10)
                f.seek(pos)
                f.write(data*float_coeff)

        self.logger.info("Normilize [ END ]; Saves to [ %s ]..." % in_filepath )


    # -------------------------------------------------------------------------


    @NLogger.wrap('DEBUG')
    def _vst_plugin_chain_process_file(self, chain, in_file, out_file):

        temp_left = VstHost.allocate_float_buffer(self._buffer_size)
        temp_right = VstHost.allocate_float_buffer(self._buffer_size)

        l_index = r_index = 0
        if in_file.channels > 1:
            r_index = 1

        for block in in_file.blocks(blocksize=self._buffer_size, always_2d=True):

            block_len = len(block)
            block_rl = block.transpose()

            in_left = block_rl[l_index].astype(numpy.float32).ctypes.data
            in_right = block_rl[r_index].astype(numpy.float32).ctypes.data

            VstHost.copy_buffer(temp_left, in_left, block_len)
            VstHost.copy_buffer(temp_right, in_right, block_len)
            buf_in = [ temp_left, temp_right ]


            for vst_plugin in chain:

                if vst_plugin.input_channels > len(buf_in):
                    for ch in range(vst_plugin.input_channels - len(buf_in)):
                        p = buf_in[ch]
                        buf_in.append( p )

                vst_plugin.process_replacing( buf_in, vst_plugin.out_buffers, block_len )
                buf_in = vst_plugin.out_buffers


            out_left_np = numpy.ctypeslib.as_array( ctypes.cast(chain[-1].out_buffers[0], ctypes.POINTER(ctypes.c_float)), shape=(block_len,) )
            if r_index:
                out_right_np = numpy.ctypeslib.as_array( ctypes.cast(chain[-1].out_buffers[1], ctypes.POINTER(ctypes.c_float)), shape=(block_len,) )
                out_left_np = numpy.column_stack((out_left_np, out_right_np))
            #
            out_file.write(out_left_np)

        VstHost.free_buffer(temp_left)
        VstHost.free_buffer(temp_right)

    # -------------------------------------------------------------------------

    @NLogger.wrap('DEBUG')
    def procces_file(self, job_file, chain_name, infilepath, outfilepath):
        """ """
        start = time.time()

        # open json job file
        try:
            with open(job_file, "r") as f:
                json_data = json.load(f)
            f = os.path.basename(job_file)
        except Exception as e:
            json_data = job_file
            f = "json dict"

        self.logger.info("[ START.... ] - %s - %s - %s - %s " % (f, chain_name, os.path.basename(infilepath), os.path.basename(outfilepath)))

        json_list = json_data["plugins_chain"][chain_name]

        # open input audio file
        in_file = soundfile.SoundFile(infilepath, mode='r', closefd=True)

        # create vst plugins chain for current job
        _plugin_chain = self._vst_plugin_chain_create_list(json_list, in_file.samplerate)

        # create output audio file
        out_file = soundfile.SoundFile(outfilepath, mode='w', samplerate=in_file.samplerate, channels=in_file.channels, subtype=in_file.subtype, closefd=True)

        # process all plugins in job
        self._vst_plugin_chain_process_file(_plugin_chain, in_file, out_file)

        # close audiofiles
        in_file.close()
        out_file.close()
        end_time = time.time()-start
        self.logger.info("[ COMPLITE ] - %s - %s - %s - %s " % (f, chain_name, os.path.basename(infilepath), os.path.basename(outfilepath)))
        self.logger.info("[ END ] - Elapsed time: [ %s ]\n" % end_time)
