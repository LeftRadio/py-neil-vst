
import setuptools
from pathlib import Path
import os
import os.path
from Cython.Build import cythonize

this_directory = os.path.dirname(__file__)
packages = setuptools.find_packages()
print(this_directory, packages)


ext_modules = cythonize( [
        'neil_vst/vst_host.pyx',
        'neil_vst/vst_plugin.pyx',
        'neil_vst/vst_chain_worker.pyx',
        'neil_vst/logger.pyx',
        'neil_vst/vst_exceptions.pyx'
],
        compiler_directives={
            'language_level': "3"
            # 'optimize.use_switch': False,
            # 'optimize.unpack_method_calls': False
        },

)

# workaround for https://github.com/cython/cython/issues/1480
for module in ext_modules:
    module.include_dirs = [ this_directory + "/neil_vst/vst_sdk_includes" ]

with open( str(this_directory) + '/README.md', "r" ) as f:
    long_description = f.read()

setuptools.setup(
    name='neil_vst',
    version='0.1.0',
    ext_modules=ext_modules,
    packages=packages,
    license='MIT',
    description='Cython-based simple VST 2.4 Host and VST Plugins wrapper. Fast work and clean python object-oriented interface',
    long_description=long_description,
    long_description_content_type='text/markdown',
    install_requires=[
       'Cython>=0.29.19',
       'SoundFile>=0.10.3.post1',
       'numpy>=1.19.3'
    ],
    author='Vladislav Kamenev',  # Type in your name
    author_email='',
    url='https://github.com/leftradio/neil_vst',
    keywords=['vst', 'plugin', 'cython'],
    classifiers=[
        'Development Status :: 4 - Beta',
        'Intended Audience :: Developers',
        'License :: OSI Approved :: MIT License',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3.7',
        'Programming Language :: Python :: 3.8',
        'Programming Language :: Python :: 3.9'
    ]
)
