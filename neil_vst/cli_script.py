
import os
import time
import datetime
import argparse

from multiprocessing import Process

from neil_vst.vst_host import VstHost
from neil_vst.vst_plugin import VstPlugin
from neil_vst.vst_chain_worker import VstChainWorker
from neil_vst.vst_exceptions import VST_ChainWorkException


def _file_thread_worker(job_file, in_file, out_file, buffer_size, verbose, vst_info):

    try:
        worker = VstChainWorker(buffer_size=buffer_size, log_level=("DEBUG" if verbose else "INFO"), display_info=vst_info)
        worker.procces_file(job_file, in_file, out_file)
    except Exception as e:
        worker.logger.error("Chain Worker for [ %s ], original message: [ %s ]" % (os.path.basename(in_file), str(e)))


def do_all_files_in_folder(in_folder, out_folder, job_file, buffer_size, verbose, vst_info):

    in_files = [ os.path.join(in_folder, f) for f in os.listdir(in_folder) if f.endswith(('.wav', '.aiff', '.flac', '.ogg')) ]
    out_files = [ os.path.abspath(os.path.join(out_folder, os.path.basename(f))) for f in in_files ]

    work_threads = []
    for in_file, out_file in zip(in_files, out_files):
        work_threads.append(
            Process(target=_file_thread_worker, args=(job_file, in_file, out_file, buffer_size, verbose, vst_info))
        )

    [ wt.start() for wt in work_threads ]
    [ wt.join() for wt in work_threads ]


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('-f', '--folder', type=str, default=".", help='folder with input audio files (default: %(default)s)')
    parser.add_argument('-j', '--job', type=str, help='JSON job file')
    parser.add_argument('-o', '--output', type=str, default="./out", help='output folder for audio files (default: %(default)s)')
    parser.add_argument('-b', '--buffersize', type=int, default=8096, help='buffer size in bytes [1024...65536] (default: %(default)s)')
    parser.add_argument('-v', '--verbose', action="store_true", help='verbose logging (default: %(default)s)')
    parser.add_argument('-i', '--info', action="store_true", help='show all parameters info for loaded VST (default: %(default)s)')

    args = parser.parse_args()

    if args.buffersize < 1024 or args.buffersize > 65536:
        parser.error('blocksize must be in range [1024...65536]')

    return args


def main():
    args = parse_args()

    start_time = time.time()
    print( "[ MAIN START ]" )

    do_all_files_in_folder(args.folder, args.output, args.job, args.buffersize, args.verbose, args.info)

    end_time = datetime.timedelta( seconds=(time.time()-start_time).split(".")[0] )
    print( "[ MAIN END ] - Elapsed time: [ %s ]" % end_time )


if __name__ == '__main__':
    main()

