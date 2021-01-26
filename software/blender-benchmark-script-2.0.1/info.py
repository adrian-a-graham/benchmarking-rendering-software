import dataclasses as dc
import enum
import multiprocessing
import platform
import subprocess
import sys
from typing import Optional, Dict, List, Any

import _cycles
import bpy

from vendor import distro, cpu_cores


class DeviceType(enum.Enum):
    CPU: str = 'CPU'
    OpenCL: str = 'OPENCL'
    CUDA: str = 'CUDA'
    OptiX: str = 'OPTIX'


@dc.dataclass
class Device:
    name: str
    type: DeviceType
    is_display: bool

    def to_dict(self) -> Dict[str, object]:
        if self.type == DeviceType.CPU:
            return {'name': self.name, 'type': self.type.value}
        else:
            return {'name': self.name, 'type': self.type.value, 'is_display': self.is_display}


@dc.dataclass
class ComputeDevice(Device):
    cycles_device: Any


def _get_all_devices() -> List[Device]:
    return [
        Device(
            name=name.replace(' (Display)', ''),
            type=DeviceType(type),
            is_display='(Display)' in name,
        )
        for name, type, *_ in _cycles.available_devices('')
    ]


def _get_compute_devices() -> List[ComputeDevice]:
    return [
        ComputeDevice(
            name=d.name.replace(' (Display)', ''),
            type=device_type,
            is_display='(Display)' in d.name,
            cycles_device=d,
        )
        for device_type in DeviceType
        for d in bpy.context.preferences.addons['cycles'].preferences.get_devices_for_type(
            device_type.value
        )
    ]


@dc.dataclass
class CPUTopology:
    sockets: int
    cores: int
    threads: int


def _get_cpu_topology() -> CPUTopology:
    """
    Get topology information (number of sockets, physical and logical threads)
    of the system CPUs.
    """
    sockets: int
    cores: int
    if not sys.platform.startswith('win'):
        cores_info = cpu_cores.CPUCoresCounter.factory()  # type: ignore
        sockets = cores_info.get_physical_processors_count()
        cores = cores_info.get_physical_cores_count()
    else:
        sockets = int(
            subprocess.check_output(
                ('wmic', 'computersystem', 'get', 'NumberOfProcessors', '/value'), text=True
            )
            .strip()
            .split('=')[1]
        )

        cores = sum(
            int(line.strip().split('=')[1])
            for line in subprocess.check_output(
                ('wmic', 'cpu', 'get', 'NumberOfCores', '/value'), text=True
            )
            .strip()
            .split('\n')
            if line.strip()
        )

    return CPUTopology(sockets=sockets, cores=cores, threads=multiprocessing.cpu_count())


def get_system_info() -> Dict[str, object]:
    system: str = platform.system()

    dist_name: Optional[str] = None
    dist_version: Optional[str] = None
    if system == 'Linux':
        dist_name, dist_version, *_ = distro.linux_distribution()  # type: ignore

    cpu_topology = _get_cpu_topology()
    return {
        'bitness': platform.architecture()[0],
        'machine': platform.machine(),
        'system': platform.system(),
        'dist_name': dist_name,
        'dist_version': dist_version,
        'devices': [d.to_dict() for d in _get_all_devices()],
        'num_cpu_sockets': cpu_topology.sockets,
        'num_cpu_cores': cpu_topology.cores,
        'num_cpu_threads': cpu_topology.threads,
    }


def get_blender_version() -> Dict[str, object]:
    return {
        'version': bpy.app.version_string,
        'build_date': bpy.app.build_date.decode('utf-8'),
        'build_time': bpy.app.build_time.decode('utf-8'),
        'build_commit_date': bpy.app.build_commit_date.decode('utf-8'),
        'build_commit_time': bpy.app.build_commit_time.decode('utf-8'),
        'build_hash': bpy.app.build_hash.decode('utf-8'),
    }
