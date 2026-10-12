async function copyText(text) {
    if (navigator.clipboard?.writeText) {
        try { await navigator.clipboard.writeText(text); return; } catch {}
    }
    const previous = document.activeElement;
    const textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.cssText = 'position:fixed;left:-9999px;top:0';
    document.body.append(textarea);
    textarea.select();
    try {
        if (!document.execCommand('copy')) throw Error('Clipboard unavailable');
    } finally {
        textarea.remove();
        previous?.focus();
    }
}

function installCopyButtons(root = document) {
    for (const target of root.querySelectorAll('pre, textarea, [data-copy]')) {
        if (target.dataset.copyReady) continue;
        target.dataset.copyReady = 'true';
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'secondary copy-button';
        button.textContent = 'Copy';
        const label = target.dataset.copyLabel || target.id?.replaceAll('-', ' ') || 'text';
        button.setAttribute('aria-label', 'Copy ' + label);
        button.onclick = async () => {
            button.disabled = true;
            try {
                await copyText(target.tagName === 'TEXTAREA' ? target.value : target.textContent);
                button.textContent = 'Copied';
            } catch { button.textContent = 'Copy failed'; }
            finally {
                button.disabled = false;
                setTimeout(() => { button.textContent = 'Copy'; }, 2000);
            }
        };
        target.insertAdjacentElement('beforebegin', button);
    }
}
