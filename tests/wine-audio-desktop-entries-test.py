import ctypes as C
import json
from pathlib import Path
import sys


glib = C.CDLL(sys.argv[1])
glib.g_key_file_new.restype = C.c_void_p
glib.g_key_file_load_from_file.argtypes = [C.c_void_p, C.c_char_p, C.c_int, C.c_void_p]
glib.g_key_file_load_from_file.restype = C.c_int
glib.g_key_file_get_string.argtypes = [C.c_void_p, C.c_char_p, C.c_char_p, C.c_void_p]
glib.g_key_file_get_string.restype = C.c_void_p
glib.g_key_file_free.argtypes = [C.c_void_p]
glib.g_free.argtypes = [C.c_void_p]
glib.g_shell_parse_argv.argtypes = [C.c_char_p, C.POINTER(C.c_int), C.POINTER(C.POINTER(C.c_char_p)), C.c_void_p]
glib.g_shell_parse_argv.restype = C.c_int
glib.g_strfreev.argtypes = [C.POINTER(C.c_char_p)]
results = []
expected = {
    'garritan-cfx.desktop': (
        'Garritan CFX Concert Grand', '/mnt/games/Audio/Garritan-CFX',
        [r'C:\Program Files\Garritan\CFX Concert Grand\CFX Concert Grand x64.exe'],
    ),
    'garritan-cfx-desktop.desktop': (
        'Garritan CFX - Wine Desktop', '/mnt/games/Audio/Garritan-CFX',
        ['explorer.exe', '/desktop=CFX,1024x768'],
    ),
    'vsl-concert-d274.desktop': (
        'VSL Concert D-274', '/mnt/games/Audio/D-274',
        [r'C:\Program Files\VSL\Vienna Synchron Pianos\Vienna Synchron Pianos.exe'],
    ),
    'vsl-concert-d274-desktop.desktop': (
        'VSL Concert D-274 - Wine Desktop', '/mnt/games/Audio/D-274',
        ['explorer.exe', '/desktop=D-274,1024x768'],
    ),
}

bitwig_package = Path(sys.argv[2])

for filename in sys.argv[3:]:
    keyfile = glib.g_key_file_new()
    assert glib.g_key_file_load_from_file(keyfile, filename.encode(), 0, None)
    def value(key):
        pointer = glib.g_key_file_get_string(keyfile, b'Desktop Entry', key.encode(), None)
        assert pointer, key
        text = C.string_at(pointer).decode()
        glib.g_free(pointer)
        return text
    argc = C.c_int()
    argv = C.POINTER(C.c_char_p)()
    assert glib.g_shell_parse_argv(value('Exec').encode(), C.byref(argc), C.byref(argv), None)
    arguments = [argv[index].decode() for index in range(argc.value)]
    glib.g_strfreev(argv)
    desktop = Path(filename).name
    if desktop == 'vsl-concert-d274-low-latency.desktop':
        assert value('Terminal') == 'true'
        assert value('Name') == 'VSL Concert D-274 - Low Latency Carla'
        assert value('Path') == '/mnt/games/Audio/D-274'
        assert len(arguments) == 1
        program = Path(arguments[0])
        assert program.name == 'vsl-concert-d274-low-latency' and program.is_file()
        results.append({'file': filename, 'name': value('Name'), 'arguments': arguments})
        glib.g_key_file_free(keyfile)
        continue
    assert value('Terminal') == 'false'
    if desktop == 'com.bitwig.BitwigStudio.desktop':
        assert value('Name') == 'Bitwig Studio'
        assert arguments == [str(bitwig_package / 'bin/bitwig-studio')]
        assert Path(arguments[0]).is_file()
        assert value('StartupWMClass') == 'com.bitwig.BitwigStudio'
        assert {'daw', 'bitwig', 'audio', 'midi'} <= set(value('Keywords').split(';'))
        icon = bitwig_package / 'share/icons/hicolor/scalable/apps/com.bitwig.BitwigStudio.svg'
        assert value('Icon') == str(icon) and icon.is_file()
        results.append({'file': filename, 'name': value('Name'), 'arguments': arguments})
        glib.g_key_file_free(keyfile)
        continue
    assert Path(arguments[0]).name == 'env'
    assert arguments[1] == f"WINEPREFIX={value('Path')}/prefix"
    assert 'WINEDLLOVERRIDES=winemenubuilder.exe=d' in arguments
    assert 'WINEDEBUG=-all' in arguments
    assert not any(arg.startswith(('HOME=', 'LD_LIBRARY_PATH=')) for arg in arguments)
    name, root, tail = expected[Path(filename).name]
    assert value('Name') == name
    assert value('Path') == root
    assert arguments[-len(tail):] == tail
    if Path(filename).name in ('garritan-cfx.desktop', 'vsl-concert-d274.desktop'):
        assert Path(arguments[-2]).name == 'wine'
        assert 'explorer.exe' not in arguments
        assert not any(argument.startswith('/desktop=') for argument in arguments)
    results.append({'file': filename, 'name': value('Name'), 'arguments': arguments})
    glib.g_key_file_free(keyfile)

assert {Path(result['file']).name for result in results} == set(expected) | {
    'com.bitwig.BitwigStudio.desktop', 'vsl-concert-d274-low-latency.desktop',
}
print(json.dumps(results, indent=2))
