# Ensure CASA is installed
from .check_imports import is_casa_installed, is_spectral_cube_installed
from importlib import import_module

casa_enabled = is_casa_installed()
spectral_cube_enabled = is_spectral_cube_installed()

try:
    from .version import version as __version__
except ImportError:
    __version__ = "dev"

from .handlerAlmaDownload import AlmaDownloadHandler
from .handlerKeys import KeyHandler
from .handlerRelease import ReleaseHandler
from .phangsLogger import setup_logger

__all__ = [
    "AlmaDownloadHandler",
    "KeyHandler",
    "ReleaseHandler",
    "setup_logger",
]

_LAZY_ATTRS = {}

# Modules that require CASA to be installed
if casa_enabled:
    _LAZY_ATTRS.update({
        "ImagingChunkedHandler": ".handlerImagingChunked",
        "ImagingHandler": ".handlerImaging",
        "PostProcessHandler": ".handlerPostprocess",
        "SingleDishHandler": ".handlerSingleDish",
        "TestImagingHandler": ".handlerTestImaging",
        "VisHandler": ".handlerVis",
    })
    __all__.extend(_LAZY_ATTRS.keys())

# Modules that require spectral-cube to be installed
if spectral_cube_enabled:
    from .handlerDerived import DerivedHandler
    __all__.append("DerivedHandler")


def __getattr__(name):
    module_name = _LAZY_ATTRS.get(name)
    if module_name is None:
        raise AttributeError(f"module {__name__!r} has no attribute {name!r}")

    module = import_module(module_name, __name__)
    value = getattr(module, name)
    globals()[name] = value
    return value
