import { computed, nextTick, ref, watch } from 'vue';
import { useMutationObserver, useResizeObserver } from '@vueuse/core';

const TOOLBAR_GAP = 8;
const MORE_BUTTON_WIDTH = 32;

// The flex container already excludes the send slot and its gap.
export function useToolbarOverflow(container, items) {
  const availableWidth = ref(0);
  const measuredItems = ref([]);
  const widths = new Map();
  const isMeasured = ref(false);

  const measure = async () => {
    await nextTick();
    if (!container.value) return;
    measuredItems.value = items.value.flatMap(item => {
      const element = container.value.querySelector(
        `[data-toolbar-item="${item.key}"]`
      );
      const button = element?.querySelector('button');
      // Contact requests and video calls can render no button at all.
      if (!button) return [];
      if (element.offsetWidth) widths.set(item.key, element.offsetWidth);
      return [
        {
          ...item,
          disabled: button.disabled,
          width: widths.get(item.key) || 0,
        },
      ];
    });
    isMeasured.value = true;
  };

  useResizeObserver(container, entries => {
    availableWidth.value = entries[0].contentRect.width;
    measure();
  });
  useMutationObserver(container, measure, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['disabled'],
  });
  watch(items, measure, { immediate: true, flush: 'post' });

  const hiddenKeys = computed(() => {
    const remaining = [...measuredItems.value];
    const hidden = [];
    const totalWidth = () =>
      remaining.reduce((total, item) => total + item.width, 0) +
      Math.max(0, remaining.length - 1) * TOOLBAR_GAP +
      (hidden.length
        ? MORE_BUTTON_WIDTH + (remaining.length ? TOOLBAR_GAP : 0)
        : 0);
    const ranked = [...remaining].sort((a, b) => a.hideRank - b.hideRank);
    while (totalWidth() > availableWidth.value && ranked.length) {
      const item = ranked.shift();
      hidden.push(item.key);
      remaining.splice(
        remaining.findIndex(entry => entry.key === item.key),
        1
      );
    }
    return hidden;
  });
  const hiddenItems = computed(() =>
    measuredItems.value.filter(item => hiddenKeys.value.includes(item.key))
  );

  return { hiddenKeys, hiddenItems, isMeasured };
}
