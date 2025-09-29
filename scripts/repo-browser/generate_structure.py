#!/usr/bin/env python3
import os
import json
import sys

def scan_directory(path, base):
    result = {}
    try:
        for item in sorted(os.listdir(path)):
            if item.startswith('.') or item in ['index.html', 'browser.js', 'structure.json']:
                continue
            full_path = os.path.join(path, item)
            
            if os.path.isdir(full_path):
                result[item] = scan_directory(full_path, base)
            else:
                size = os.path.getsize(full_path)
                if item.endswith('-openrc.apk'):
                    ext = 'openrc'
                elif item.endswith('.tar.gz'):
                    ext = 'tar.gz'
                elif '.' in item:
                    ext = item.split('.')[-1]
                else:
                    ext = 'file'
                result[item] = {'type': ext, 'size': size}
    except PermissionError:
        pass
    return result

if __name__ == '__main__':
    base = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('REPO_DIR', 'gh-pages')
    structure = scan_directory(base, base)
    print(json.dumps(structure, indent=2))