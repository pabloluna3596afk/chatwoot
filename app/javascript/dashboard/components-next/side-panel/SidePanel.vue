<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  provide,
  ref,
  useId,
  watch,
} from 'vue';
import { useScrollLock } from '@vueuse/core';
import { showModal } from 'dashboard/helper/overlayFocus';
import Button from 'dashboard/components-next/button/Button.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const props = defineProps({
  ariaLabel: { type: String, default: '' },
  title: {
    type: String,
    default: '',
  },
  description: {
    type: String,
    default: '',
  },
  width: {
    type: String,
    default: 'xl',
    validator: value => ['md', 'lg', 'xl', '2xl', '3xl'].includes(value),
  },
  closeOnClickOutside: {
    type: Boolean,
    default: true,
  },
});

// `afterLeave` fires once the slide-out transition finishes, so consumers
// mounted with v-if can wait for it before unmounting the panel.
const emit = defineEmits(['close', 'afterLeave']);

const MAX_WIDTH_CLASSES = {
  md: 'max-w-md',
  lg: 'max-w-lg',
  xl: 'max-w-xl',
  '2xl': 'max-w-2xl',
  '3xl': 'max-w-3xl',
};

const titleId = useId();
const descriptionId = useId();
const isOpen = ref(false);
const panelRef = ref(null);
provide('dialogPortalTarget', panelRef);
const isScrollLocked = useScrollLock(document.body);
const sourceRef = ref(null);
let lockedContainers = [];
const unlockContainers = () => {
  lockedContainers.forEach(element =>
    element.classList.remove('!overflow-hidden')
  );
  lockedContainers = [];
};
watch(isOpen, open => {
  if (!open) {
    unlockContainers();
    return;
  }
  let element = sourceRef.value?.parentElement;
  while (element && element !== document.body) {
    if (
      /(auto|scroll)/.test(getComputedStyle(element).overflowY) &&
      !element.classList.contains('!overflow-hidden')
    ) {
      element.classList.add('!overflow-hidden');
      lockedContainers.push(element);
    }
    element = element.parentElement;
  }
});

const maxWidthClass = computed(() => MAX_WIDTH_CLASSES[props.width]);

const open = async () => {
  if (isOpen.value) return;
  isOpen.value = true;
  await nextTick();
  if (isOpen.value) showModal(panelRef.value);
};

// Locking the page and moving focus both force layout. Doing that in the frame the panel mounts
// in delays the slide by a frame, so it waits until the panel has arrived.
const onAfterEnter = () => {
  isScrollLocked.value = true;
};

const close = () => {
  if (!isOpen.value) return;
  panelRef.value?.close();
  isOpen.value = false;
  isScrollLocked.value = false;
  emit('close');
};

const onOverlayClick = () => {
  if (props.closeOnClickOutside) close();
};

const onBackdropClick = event => {
  const rect = panelRef.value.getBoundingClientRect();
  if (
    event.clientX < rect.left ||
    event.clientX > rect.right ||
    event.clientY < rect.top ||
    event.clientY > rect.bottom
  )
    onOverlayClick();
};

onBeforeUnmount(() => {
  unlockContainers();
  isScrollLocked.value = false;
});

defineExpose({ open, close });
</script>

<template>
  <span ref="sourceRef" class="hidden" />
  <TeleportWithDirection to="body">
    <Transition
      enter-active-class="transition-transform duration-300 ease-[cubic-bezier(0.4,0,0.2,1)]"
      enter-from-class="translate-x-[calc(100%+0.75rem)] rtl:translate-x-[calc(-100%-0.75rem)]"
      leave-active-class="transition-transform duration-200 ease-in"
      leave-to-class="translate-x-[calc(100%+0.75rem)] rtl:translate-x-[calc(-100%-0.75rem)]"
      @after-enter="onAfterEnter"
      @after-leave="emit('afterLeave')"
    >
      <dialog
        v-if="isOpen"
        ref="panelRef"
        :aria-labelledby="title || $slots.header ? titleId : undefined"
        :aria-label="
          title || $slots.header ? undefined : ariaLabel || undefined
        "
        :aria-describedby="
          description && !$slots.header ? descriptionId : undefined
        "
        tabindex="-1"
        class="fixed m-0 border-0 p-0 start-auto max-h-none h-[calc(100dvh-1.5rem)] [&::backdrop]:bg-n-alpha-black1 z-50 flex flex-col w-[calc(100%-1.5rem)] overflow-hidden rounded-xl shadow-lg outline outline-1 outline-n-container inset-y-3 end-3 bg-n-solid-1 will-change-transform"
        :class="maxWidthClass"
        @cancel.prevent="$event.target === panelRef && close()"
        @close="$event.target === panelRef && close()"
        @click="onBackdropClick"
      >
        <header
          class="flex justify-between flex-shrink-0 gap-4 px-6 py-5 border-b border-n-weak"
          :class="$slots.header ? 'items-start' : 'items-center'"
        >
          <div :id="titleId" class="min-w-0">
            <slot name="header">
              <div class="min-w-0">
                <h3 class="text-base font-medium truncate text-n-slate-12">
                  {{ title }}
                </h3>
                <p
                  v-if="description"
                  :id="descriptionId"
                  class="mt-1 mb-0 text-sm text-n-slate-11"
                >
                  {{ description }}
                </p>
              </div>
            </slot>
          </div>
          <div class="flex items-center gap-1 shrink-0 -me-2">
            <slot name="header-actions" />
            <Button
              ghost
              slate
              sm
              icon="i-lucide-x"
              class="min-h-11 min-w-11 md:min-h-0 md:min-w-0"
              :aria-label="$t('GENERAL.CLOSE')"
              @click="close"
            />
          </div>
        </header>
        <div class="flex-1 min-h-0 px-6 py-5 overflow-y-auto">
          <slot />
        </div>
        <footer
          v-if="$slots.footer"
          class="flex-shrink-0 px-6 py-4 pb-[max(1rem,env(safe-area-inset-bottom))] md:pb-4 border-t border-n-weak"
        >
          <slot name="footer" />
        </footer>
      </dialog>
    </Transition>
  </TeleportWithDirection>
</template>
