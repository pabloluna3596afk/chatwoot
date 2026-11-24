import { onMounted, onUnmounted, shallowRef } from 'vue';

export function useVisualViewportHeight() {
  const isIOSViewport = shallowRef(false);
  let viewport;
  const updateHeight = () => {
    // Safari can scroll the document as well as pan the visual viewport.
    if (window.scrollX || window.scrollY) window.scrollTo(0, 0);
    document.documentElement.style.setProperty(
      '--app-height',
      `${viewport.height}px`
    );
    document.documentElement.style.setProperty(
      '--app-offset-top',
      `${viewport.offsetTop}px`
    );
  };

  onMounted(() => {
    const isIOS =
      /iPhone|iPad/.test(navigator.userAgent) ||
      (navigator.maxTouchPoints > 1 && /Macintosh/.test(navigator.userAgent));
    if (!isIOS || !window.visualViewport) return;

    viewport = window.visualViewport;
    isIOSViewport.value = true;
    updateHeight();
    viewport.addEventListener('resize', updateHeight);
    viewport.addEventListener('scroll', updateHeight);
  });

  onUnmounted(() => {
    if (!viewport) return;

    viewport.removeEventListener('resize', updateHeight);
    viewport.removeEventListener('scroll', updateHeight);
    document.documentElement.style.removeProperty('--app-height');
    document.documentElement.style.removeProperty('--app-offset-top');
  });

  return { isIOSViewport };
}
