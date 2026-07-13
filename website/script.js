const header = document.querySelector('.site-header');
const menuButton = document.querySelector('.menu-button');

if (header && menuButton) {
  const setMenuOpen = (open) => {
    header.classList.toggle('open', open);
    menuButton.setAttribute('aria-expanded', String(open));
    menuButton.setAttribute('aria-label', open ? 'Close navigation' : 'Open navigation');
  };

  menuButton.addEventListener('click', () => {
    setMenuOpen(!header.classList.contains('open'));
  });

  header.querySelectorAll('nav a').forEach((link) => {
    link.addEventListener('click', () => setMenuOpen(false));
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && header.classList.contains('open')) {
      setMenuOpen(false);
      menuButton.focus();
    }
  });

  document.addEventListener('click', (event) => {
    if (header.classList.contains('open') && !header.contains(event.target)) {
      setMenuOpen(false);
    }
  });

  window.matchMedia('(min-width: 901px)').addEventListener('change', (event) => {
    if (event.matches) {
      setMenuOpen(false);
    }
  });
}
