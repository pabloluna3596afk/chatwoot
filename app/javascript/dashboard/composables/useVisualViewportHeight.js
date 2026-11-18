import { onMounted, onUnmounted } from 'vue';

export function useVisualViewportHeight() {
  let viewport;
  const updateHeight = () => {
    document.documentElement.style.setProperty(
      '--app-height',
      `${viewport.height}px`
    );
  };

  onMounted(() => {
    const isIOS =
      /iPhone|iPad/.test(navigator.userAgent) ||
      (navigator.maxTouchPoints > 1 && /Macintosh/.test(navigator.userAgent));
    if (!isIOS || !window.visualViewport) return;

    viewport = window.visualViewport;
    updateHeight();
    viewport.addEventListener('resize', updateHeight);
    viewport.addEventListener('scroll', updateHeight);
  });

  onUnmounted(() => {
    if (!viewport) return;

    viewport.removeEventListener('resize', updateHeight);
    viewport.removeEventListener('scroll', updateHeight);
    document.documentElement.style.removeProperty('--app-height');
  });
}
