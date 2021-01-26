import bpy

import info
from info import DeviceType, Device, ComputeDevice

def enable_gpus(device_type, use_cpus=False):
  preferences = bpy.context.preferences
  cycles_preferences = preferences.addons["cycles"].preferences
  cuda_devices, opencl_devices = cycles_preferences.get_devices()

  if device_type == "CUDA":
    devices = cuda_devices
  elif device_type == "OPENCL":
    devices = opencl_devices
  else:
    raise RuntimeError("Unsupported device type")

  activated_gpus = []

  for device in devices:
    if device.type == "CPU":
      if use_cpus:
        device.use = True
      else:
        device.use = False
    else:
      device.use = True
      d = ComputeDevice(
              name=device.name,
              type=DeviceType('CUDA'),
              is_display=False,
              cycles_device=device
      )
      activated_gpus.append(d)

  cycles_preferences.compute_device_type = device_type
  bpy.context.scene.cycles.device = "GPU"

  return activated_gpus

#enable_gpus("CUDA")
