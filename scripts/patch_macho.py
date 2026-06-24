#!/usr/bin/env python3
import sys
import os

def patch_macho_data(data):
    if len(data) < 32:
        return data, False
    
    magic = int.from_bytes(data[0:4], 'little')
    if magic == 0xfeedfacf:
        is_little = True
    elif magic == 0xcffaedfe:
        is_little = False
    elif magic == 0xfeedface: # 32-bit Mach-O
        is_little = True
    elif magic == 0xcefaedfe:
        is_little = False
    else:
        # Not a Mach-O file
        return data, False
        
    # Read header fields
    header_size = 32 if magic in (0xfeedfacf, 0xcffaedfe) else 28
    
    def read_u32(offset):
        b = data[offset:offset+4]
        return int.from_bytes(b, 'little' if is_little else 'big')
        
    def write_u32(offset, val):
        b = val.to_bytes(4, 'little' if is_little else 'big')
        data[offset:offset+4] = b

    ncmds = read_u32(16)
    
    offset = header_size
    modified = False
    
    for _ in range(ncmds):
        if offset + 8 > len(data):
            break
        cmd = read_u32(offset)
        cmdsize = read_u32(offset + 4)
        if cmdsize < 8 or offset + cmdsize > len(data):
            break
            
        if cmd == 0x25: # LC_VERSION_MIN_IPHONEOS
            # Change to LC_VERSION_MIN_TVOS (0x2F)
            write_u32(offset, 0x2F)
            modified = True
        elif cmd == 0x32: # LC_BUILD_VERSION
            platform = read_u32(offset + 8)
            if platform == 2: # PLATFORM_IOS
                # Change to PLATFORM_TVOS (3)
                write_u32(offset + 8, 3)
                modified = True
                
        offset += cmdsize
        
    return data, modified

def patch_file(filepath):
    try:
        with open(filepath, 'rb') as f:
            data = bytearray(f.read())
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return False

    patched_data, modified = patch_macho_data(data)
    if modified:
        try:
            with open(filepath, 'wb') as f:
                f.write(patched_data)
            print(f"  Patched: {filepath}")
            return True
        except Exception as e:
            print(f"Error writing {filepath}: {e}")
            return False
    return False

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <file_or_directory>")
        sys.exit(1)
        
    target = sys.argv[1]
    if os.path.isfile(target):
        patch_file(target)
    elif os.path.isdir(target):
        for root, dirs, files in os.walk(target):
            for file in files:
                patch_file(os.path.join(root, file))
    else:
        print(f"Target not found: {target}")
        sys.exit(1)
