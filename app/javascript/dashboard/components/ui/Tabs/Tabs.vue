<script setup>
import { ref, useTemplateRef, provide, computed, watch } from 'vue';
import { useElementSize } from '@vueuse/core';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  index: {
    type: Number,
    default: 0,
  },
  border: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['change']);
const { t } = useI18n();

const tabsContainer = useTemplateRef('tabsContainer');
const tabsList = useTemplateRef('tabsList');

const { width: containerWidth } = useElementSize(tabsContainer);
const { width: listWidth } = useElementSize(tabsList);

const hasScroll = ref(false);

const activeIndex = computed({
  get: () => props.index,
  set: newValue => {
    emit('change', newValue);
  },
});

provide('activeIndex', activeIndex);
provide('updateActiveIndex', index => {
  activeIndex.value = index;
});

const computeScrollWidth = () => {
  if (tabsContainer.value && tabsList.value) {
    hasScroll.value = tabsList.value.scrollWidth > tabsList.value.clientWidth;
  }
};

const onScrollClick = direction => {
  if (tabsContainer.value && tabsList.value) {
    let scrollPosition = tabsList.value.scrollLeft;
    scrollPosition += direction === 'left' ? -100 : 100;
    tabsList.value.scrollTo({
      top: 0,
      left: scrollPosition,
      behavior: 'smooth',
    });
  }
};

const onTabKeydown = event => {
  if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
  const buttons = Array.from(
    tabsList.value?.querySelectorAll('button[role="tab"]:not(:disabled)') || []
  );
  if (!buttons.length) return;

  const currentIndex = buttons.indexOf(
    event.target.closest('button[role="tab"]')
  );
  if (currentIndex === -1) return;

  event.preventDefault();
  let nextIndex;
  if (event.key === 'Home') nextIndex = 0;
  else if (event.key === 'End') nextIndex = buttons.length - 1;
  else {
    const isRtl = getComputedStyle(tabsList.value).direction === 'rtl';
    const direction = event.key === 'ArrowRight' ? 1 : -1;
    const offset = isRtl ? -direction : direction;
    nextIndex = (currentIndex + offset + buttons.length) % buttons.length;
  }

  buttons[nextIndex].focus();
  emit('change', Number(buttons[nextIndex].dataset.index));
};

// Watch for changes in element sizes with immediate execution
watch(
  [containerWidth, listWidth],
  () => {
    computeScrollWidth();
  },
  { immediate: true }
);
</script>

<template>
  <div
    ref="tabsContainer"
    class="flex"
    :class="[border && 'border-b border-b-n-weak']"
  >
    <button
      v-if="hasScroll"
      type="button"
      :aria-label="t('GENERAL.TABS.SCROLL_LEFT')"
      class="items-center rounded-none cursor-pointer flex h-auto justify-center max-sm:min-w-11 min-w-8"
      @click="onScrollClick('left')"
    >
      <fluent-icon icon="chevron-left" :size="16" />
    </button>
    <ul
      ref="tabsList"
      role="tablist"
      class="border-r-0 border-l-0 border-t-0 flex min-w-[6.25rem] py-0 px-4 list-none mb-0"
      :class="
        hasScroll
          ? 'overflow-hidden py-0 px-1 max-w-[calc(100%-5.5rem)] sm:max-w-[calc(100%-4rem)]'
          : ''
      "
      @keydown="onTabKeydown"
    >
      <slot />
    </ul>
    <button
      v-if="hasScroll"
      type="button"
      :aria-label="t('GENERAL.TABS.SCROLL_RIGHT')"
      class="items-center rounded-none cursor-pointer flex h-auto justify-center max-sm:min-w-11 min-w-8"
      @click="onScrollClick('right')"
    >
      <fluent-icon icon="chevron-right" :size="16" />
    </button>
  </div>
</template>
