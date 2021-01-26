# -*- coding: utf-8 -*-
from distutils.core import setup

packages = \
['vendor', 'vendor.cpu_cores']

package_data = \
{'': ['*']}

modules = \
['info', 'main', 'render']
setup_kwargs = {
    'name': 'blender-benchmark-script',
    'version': '2.0.0',
    'description': 'The Blender Benchmark Script',
    'long_description': None,
    'author': 'Sem Mulder',
    'author_email': 'sem@mulderke.net',
    'url': None,
    'packages': packages,
    'package_data': package_data,
    'py_modules': modules,
    'python_requires': '>=3.7.5,<4.0.0',
}


setup(**setup_kwargs)
