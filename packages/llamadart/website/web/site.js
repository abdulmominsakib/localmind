// Client behaviour for the static docs pages: theme toggle, navigation
// drawer, copy buttons, version menu, search dialog, Mermaid and the active
// table-of-contents entry.
(() => {
  const root = document.documentElement;

  // Theme. The head script applies the stored or system theme before paint.
  const setTheme = (theme) => {
    root.setAttribute('data-theme', theme);
    try {
      localStorage.setItem('theme', theme);
    } catch (_) {}
  };
  const systemDark = matchMedia('(prefers-color-scheme: dark)');
  systemDark.addEventListener('change', (event) => {
    let stored = null;
    try {
      stored = localStorage.getItem('theme');
    } catch (_) {}
    if (!stored) root.setAttribute('data-theme', event.matches ? 'dark' : 'light');
  });

  // Navigation drawer (narrow layouts).
  const drawer = document.querySelector('.sidebar-container');
  const barrier = document.querySelector('.sidebar-barrier');
  const setDrawer = (open) => {
    drawer?.classList.toggle('open', open);
    barrier?.classList.toggle('open', open);
    document.querySelector('.sidebar-toggle')?.setAttribute('aria-expanded', String(open));
    if (open) drawer?.querySelector('a.active, a')?.focus({ preventScroll: true });
  };
  drawer?.querySelector('a.active')?.scrollIntoView({ block: 'center' });

  // Search (Pagefind UI, loaded on first use).
  const dialog = document.getElementById('search-dialog');
  let pagefind;
  const loadSearch = () =>
    (pagefind ??= new Promise((resolve, reject) => {
      const css = document.createElement('link');
      css.rel = 'stylesheet';
      css.href = '/pagefind/pagefind-ui.css';
      document.head.append(css);
      const js = document.createElement('script');
      js.src = '/pagefind/pagefind-ui.js';
      js.onload = () => {
        new PagefindUI({
          element: '#search',
          showSubResults: true,
          showImages: false,
          resetStyles: false,
        });
        resolve();
      };
      js.onerror = () => {
        document.getElementById('search').textContent =
          'Search is unavailable: the search index was not built.';
        reject(new Error('pagefind'));
      };
      document.head.append(js);
    }));
  const openSearch = () => {
    if (!dialog) return;
    dialog.showModal();
    loadSearch().then(
      () => dialog.querySelector('input')?.focus(),
      () => {},
    );
  };

  const copy = (button, text) => {
    navigator.clipboard?.writeText(text).then(() => {
      const label = button.textContent;
      button.textContent = 'Copied';
      setTimeout(() => (button.textContent = label), 1500);
    });
  };

  document.addEventListener('click', (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    if (target.closest('.theme-toggle')) {
      setTheme(root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark');
    }
    if (target.closest('.sidebar-toggle')) setDrawer(true);
    if (target.closest('.sidebar-close') || target === barrier) setDrawer(false);
    if (target.closest('[data-search-open]')) openSearch();
    if (target === dialog) dialog.close();
    const copyButton = target.closest('.copy-code');
    if (copyButton) copy(copyButton, copyButton.parentElement.querySelector('pre').textContent);
    const installButton = target.closest('[data-copy]');
    if (installButton) copy(installButton, installButton.dataset.copy);
    for (const menu of document.querySelectorAll('.version-menu[open]')) {
      if (!menu.contains(target)) menu.removeAttribute('open');
    }
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      setDrawer(false);
      for (const menu of document.querySelectorAll('.version-menu[open]')) menu.removeAttribute('open');
    }
    const editing =
      event.target instanceof Element &&
      event.target.closest('input, textarea, select, [contenteditable]');
    if (
      (event.key === '/' && !editing) ||
      (event.key.toLowerCase() === 'k' && (event.metaKey || event.ctrlKey))
    ) {
      event.preventDefault();
      openSearch();
    }
  });

  // Mermaid, rendered client-side and re-rendered when the theme changes.
  const diagrams = [...document.querySelectorAll('pre.mermaid')];
  if (diagrams.length) {
    for (const diagram of diagrams) diagram.dataset.source = diagram.textContent;
    let mermaid;
    const render = async () => {
      mermaid ??= (await import('https://cdn.jsdelivr.net/npm/mermaid@11.16.1/dist/mermaid.esm.min.mjs')).default;
      mermaid.initialize({
        startOnLoad: false,
        theme: root.getAttribute('data-theme') === 'dark' ? 'dark' : 'neutral',
      });
      for (const diagram of diagrams) {
        diagram.removeAttribute('data-processed');
        diagram.textContent = diagram.dataset.source;
      }
      await mermaid.run({ nodes: diagrams });
    };
    render();
    new MutationObserver(render).observe(root, { attributes: true, attributeFilter: ['data-theme'] });
  }

  // Highlight the table-of-contents entry for the section in view.
  const tocLinks = [...document.querySelectorAll('.toc a[href*="#"]')];
  const headings = tocLinks
    .map((link) => document.getElementById(decodeURIComponent(link.hash.slice(1))))
    .filter(Boolean);
  if (headings.length) {
    const update = () => {
      let current = headings[0];
      for (const heading of headings) {
        if (heading.getBoundingClientRect().top < 120) current = heading;
      }
      for (const link of tocLinks) {
        link.classList.toggle('active', link.hash.slice(1) === current.id);
      }
    };
    addEventListener('scroll', update, { passive: true });
    update();
  }
})();
