
from setuptools import setup, find_packages

import platform

import pathlib, re
here = pathlib.Path(__file__).parent
version = re.search(r"^__version__ = ['\"]([^'\"]+)['\"]",
                    (here/"ramanimator"/"version.py").read_text(), re.M).group(1)

required = ["numpy", "pillow", "websockets"]

setup(
    name="ramanimator",
    version=version,
    description="Scripts to generate and work with indexed sprites for RAM hacking",
    author="Jengolus", 
    packages=find_packages(),
    install_requires=required,
    entry_points = {
        'console_scripts': [
            'ramanim=ramanimator.tools.send_commands:main',
            'rasave=ramanimator.tools.save_library:main',
            'rag2a=ramanimator.tools.gifs2animations:main',
        ],
    },
    )
