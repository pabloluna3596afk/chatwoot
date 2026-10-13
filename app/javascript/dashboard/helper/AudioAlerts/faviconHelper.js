// The icons are served for a year (Cache-Control), and a new brand kept the same file names, so browsers kept the old
// ones. Changing this number (and the `?v=` of the favicon links in layouts/vueapp.html.erb) makes them download again.
export const FAVICON_VERSION = '2';

const faviconUrl = (name, size) => `/${name}-${size}.png?v=${FAVICON_VERSION}`;

export const showBadgeOnFavicon = () => {
  const favicons = document.querySelectorAll('.favicon');

  favicons.forEach(favicon => {
    const newFileName = faviconUrl('favicon-badge', favicon.sizes[[0]]);
    favicon.href = newFileName;
  });
};

export const initFaviconSwitcher = () => {
  const favicons = document.querySelectorAll('.favicon');

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      favicons.forEach(favicon => {
        const oldFileName = faviconUrl('favicon', favicon.sizes[[0]]);
        favicon.href = oldFileName;
      });
    }
  });
};
