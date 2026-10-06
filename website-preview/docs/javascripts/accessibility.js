/* Make the theme's mobile disclosure labels keyboard-operable. */
(() => {
  const disclosures = [
    ['__drawer', 'Open navigation'],
    ['__search', 'Open search'],
    ['__toc', 'Open table of contents']
  ];
  for (const [id, name] of disclosures) {
    const toggle = document.getElementById(id);
    if (!toggle) continue;
    const labels = document.querySelectorAll(`label.md-header__button[for="${id}"]`);
    for (const label of labels) {
      label.setAttribute('role', 'button');
      label.setAttribute('aria-label', name);
      label.tabIndex = 0;
      const sync = () => label.setAttribute('aria-expanded', String(toggle.checked));
      toggle.addEventListener('change', sync);
      sync();
      label.addEventListener('keydown', event => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          event.stopPropagation();
          label.click();
        }
      });
    }
  }
})();
