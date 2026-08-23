import { ref, onMounted, onUnmounted } from 'vue';

const readDarkMode = () => document.body.classList.contains('dark');

export function useDarkMode() {
  const isDark = ref(readDarkMode());
  let observer;

  onMounted(() => {
    isDark.value = readDarkMode();
    observer = new MutationObserver(() => {
      isDark.value = readDarkMode();
    });
    observer.observe(document.body, {
      attributes: true,
      attributeFilter: ['class'],
    });
  });

  onUnmounted(() => {
    observer?.disconnect();
  });

  return { isDark };
}
