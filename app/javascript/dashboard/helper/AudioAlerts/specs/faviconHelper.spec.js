import {
  FAVICON_VERSION,
  initFaviconSwitcher,
  showBadgeOnFavicon,
} from '../faviconHelper';

describe('faviconHelper', () => {
  beforeEach(() => {
    document.head.innerHTML = [16, 32, 96]
      .map(
        size =>
          `<link class="favicon" rel="icon" sizes="${size}x${size}" href="/favicon-${size}x${size}.png?v=${FAVICON_VERSION}">`
      )
      .join('');
    // jsdom has no `sizes` on a link; browsers give a list like ['32x32'].
    document.querySelectorAll('.favicon').forEach(link =>
      Object.defineProperty(link, 'sizes', {
        value: [link.getAttribute('sizes')],
      })
    );
  });

  const hrefs = () =>
    [...document.querySelectorAll('.favicon')].map(link =>
      link.getAttribute('href')
    );

  it('shows the icon with the dot, with the version so the browser does not keep an old copy', () => {
    showBadgeOnFavicon();

    expect(hrefs()).toEqual([
      `/favicon-badge-16x16.png?v=${FAVICON_VERSION}`,
      `/favicon-badge-32x32.png?v=${FAVICON_VERSION}`,
      `/favicon-badge-96x96.png?v=${FAVICON_VERSION}`,
    ]);
  });

  it('goes back to the normal icon when the window is visible again', () => {
    initFaviconSwitcher();
    showBadgeOnFavicon();

    document.dispatchEvent(new Event('visibilitychange'));

    expect(hrefs()).toEqual([
      `/favicon-16x16.png?v=${FAVICON_VERSION}`,
      `/favicon-32x32.png?v=${FAVICON_VERSION}`,
      `/favicon-96x96.png?v=${FAVICON_VERSION}`,
    ]);
  });
});
