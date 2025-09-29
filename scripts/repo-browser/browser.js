let repoStructure = {};

fetch('structure.json')
    .then(res => res.json())
    .then(data => {
        repoStructure = data;
        navigate('');
    })
    .catch(err => {
        document.getElementById('fileList').innerHTML = 
            '<div class="empty">Error loading repository structure</div>';
    });

function formatSize(bytes) {
    if (!bytes) return '-';
    const units = ['B', 'KB', 'MB', 'GB'];
    let size = bytes;
    let unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
        size /= 1024;
        unitIndex++;
    }
    return size.toFixed(1) + ' ' + units[unitIndex];
}

function getIcon(type) {
    const icons = {
        folder: '📁',
        apk: '📦',
        'tar.gz': '🗜️',
        pub: '🔑',
        html: '📄'
    };
    return icons[type] || '📄';
}

function renderBreadcrumb(path) {
    const parts = path ? path.split('/').filter(Boolean) : [];
    let html = '<a href="#" onclick="navigate(\'\'); return false;">🏠 root</a>';
    let currentPath = '';
    
    parts.forEach(part => {
        currentPath += part + '/';
        html += ' / <a href="#" onclick="navigate(\'' + currentPath.slice(0, -1) + '\'); return false;">' + part + '</a>';
    });
    
    document.getElementById('breadcrumb').innerHTML = html;
}

function navigate(path) {
    const parts = path ? path.split('/').filter(Boolean) : [];
    let current = repoStructure;
    
    for (const part of parts) {
        if (current[part] && typeof current[part] === 'object' && !current[part].type) {
            current = current[part];
        } else {
            return;
        }
    }

    renderBreadcrumb(path);
    renderFileList(current, path);
}

function renderFileList(items, currentPath) {
    const fileList = document.getElementById('fileList');
    const entries = Object.entries(items).sort((a, b) => {
        const aIsDir = !a[1].type;
        const bIsDir = !b[1].type;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return a[0].localeCompare(b[0]);
    });

    if (entries.length === 0) {
        fileList.innerHTML = '<div class="empty">This directory is empty</div>';
        return;
    }

    fileList.innerHTML = entries.map(([name, data]) => {
        const isDir = !data.type;
        const icon = getIcon(isDir ? 'folder' : data.type);
        const fullPath = currentPath ? currentPath + '/' + name : name;
        const href = isDir ? '#' : fullPath;
        const onclick = isDir ? `navigate('${fullPath}'); return false;` : '';
        const className = isDir ? 'folder' : '';

        return `
            <li class="file-item">
                <span class="file-icon">${icon}</span>
                <a href="${href}" class="file-name ${className}" ${onclick ? `onclick="${onclick}"` : ''}>${name}</a>
                <span class="file-size">${isDir ? '' : formatSize(data.size)}</span>
            </li>
        `;
    }).join('');
}