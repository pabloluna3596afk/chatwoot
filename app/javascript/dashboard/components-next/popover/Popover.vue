<script setup>
import { ref, computed, watch, nextTick, provide, useId } from 'vue';
import { vOnClickOutside } from '@vueuse/components';
import {
  useBreakpoints,
  breakpointsTailwind,
  useEventListener,
} from '@vueuse/core';
import { useDropdownPosition } from 'dashboard/composables/useDropdownPosition';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { showModal } from 'dashboard/helper/overlayFocus';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const props = defineProps({
  ariaLabel: { type: String, default: '' },
  labelledby: { type: String, default: '' },
  describedby: { type: String, default: '' },
  align: {
    type: String,
    default: 'end',
    validator: v => ['start', 'end'].includes(v),
  },
  disableMobileView: {
    type: Boolean,
    default: false,
  },
  closeOnScroll: {
    type: Boolean,
    default: true,
  },
  showContentBorder: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['show', 'hide']);

const triggerId = useId();
const modalRef = ref(null);
provide('dialogPortalTarget', modalRef);
const isActive = ref(false);
const triggerRef = ref(null);
const popoverRef = ref(null);
const mobileContentRef = ref(null);

const breakpoints = useBreakpoints(breakpointsTailwind);
const belowMd = breakpoints.smaller('md');
const isMobile = computed(() => !props.disableMobileView && belowMd.value);
const showPopover = computed(() => isActive.value && !isMobile.value);

const { fixedPosition, updatePosition } = useDropdownPosition(
  triggerRef,
  popoverRef,
  showPopover,
  { align: props.align }
);

const SCROLL_CLOSE_THRESHOLD = 24;
const triggerTopAtOpen = ref(0);

const show = async () => {
  isActive.value = true;
  triggerTopAtOpen.value = triggerRef.value?.getBoundingClientRect().top ?? 0;
  if (!isMobile.value) {
    await nextTick();
    updatePosition();
  }
  emit('show');
};

const hide = () => {
  if (!isActive.value) return;
  modalRef.value?.close();
  isActive.value = false;
  emit('hide');
};

// The teleported popover tracks its trigger while ancestors scroll; allow
// small drift (trackpad inertia), but close once the trigger moves further.
useEventListener(
  window,
  'scroll',
  event => {
    if (!props.closeOnScroll || !showPopover.value) return;
    if (popoverRef.value?.contains(event.target)) return;
    const top = triggerRef.value?.getBoundingClientRect().top ?? 0;
    if (Math.abs(top - triggerTopAtOpen.value) > SCROLL_CLOSE_THRESHOLD) {
      hide();
    }
  },
  { capture: true, passive: true }
);

const toggle = async () => {
  if (isActive.value) hide();
  else await show();
};

// Native modality supplies focus containment, background isolation and restoration.
watch([isActive, isMobile], async ([active, mobile]) => {
  await nextTick();
  if (active && mobile && !modalRef.value?.open) showModal(modalRef.value);
});

// Recalculate position when switching from mobile to desktop while open
watch(isMobile, async mobile => {
  if (!isActive.value || mobile) return;
  await nextTick();
  updatePosition();
});

const handleClickOutside = event => {
  if (triggerRef.value?.contains(event.target)) return;
  hide();
};

// Selectors for teleported elements that should not trigger close
const clickOutsideIgnore = [
  'dialog[open]',
  'dialog.ProseMirror-prompt-backdrop',
  '[data-combobox-dropdown]',
  '[data-menu-popover]',
  '[data-popover-content]',
];

// An overlay opened from inside the popover teleports out of it, so its own Escape handler
// registers after this one and cannot stop it. Leave Escape to whichever overlay the key
// was pressed in; closing the popover out from under it would discard the work in progress.
const isNestedOverlay = event => {
  const overlay = event.target?.closest?.(clickOutsideIgnore.join(','));
  return Boolean(
    overlay &&
      overlay !== popoverRef.value &&
      overlay !== mobileContentRef.value
  );
};

useKeyboardEvents({
  Escape: {
    action: event => {
      if (isActive.value && !isMobile.value && !isNestedOverlay(event)) hide();
    },
    allowOnFocusedInput: true,
  },
});

defineExpose({ show, hide, toggle });
</script>

<template>
  <span :id="triggerId" ref="triggerRef" class="inline-flex" @click="toggle">
    <slot :is-open="isActive" />
  </span>

  <TeleportWithDirection to="body">
    <!-- Mobile: centered modal with backdrop -->
    <dialog
      v-if="isActive && isMobile"
      ref="modalRef"
      :aria-label="ariaLabel || undefined"
      :aria-labelledby="ariaLabel ? undefined : labelledby || triggerId"
      :aria-describedby="describedby || undefined"
      tabindex="-1"
      data-popover-backdrop
      class="fixed inset-0 m-0 border-0 p-0 w-full max-w-none h-dvh max-h-none z-[9999] flex items-start pt-[clamp(3rem,15dvh,12rem)] pb-[max(1rem,env(safe-area-inset-bottom))] justify-center bg-transparent [&::backdrop]:bg-n-alpha-black1"
      @cancel.prevent="$event.target === modalRef && hide()"
      @close="$event.target === modalRef && hide()"
    >
      <div
        ref="mobileContentRef"
        v-on-click-outside="[
          handleClickOutside,
          { ignore: clickOutsideIgnore },
        ]"
        data-popover-content
        class="relative flex flex-col w-full max-w-lg max-h-full mx-4 bg-n-alpha-3 backdrop-blur-[100px] shadow-xl rounded-xl"
      >
        <div
          class="flex-1 min-h-0 overflow-y-auto overscroll-contain rounded-xl"
        >
          <slot name="content" :hide="hide" />
        </div>
      </div>
    </dialog>

    <!-- Desktop: fixed popover -->
    <div
      v-else-if="showPopover"
      ref="popoverRef"
      v-on-click-outside="[handleClickOutside, { ignore: clickOutsideIgnore }]"
      data-popover-content
      :class="fixedPosition.class"
      :style="fixedPosition.style"
      class="flex flex-col bg-n-alpha-3 backdrop-blur-[100px] shadow-xl rounded-xl"
    >
      <div
        class="flex-1 min-h-0 overflow-y-auto overscroll-contain rounded-xl"
        :class="{ 'border border-n-strong': showContentBorder }"
      >
        <slot name="content" :hide="hide" />
      </div>
    </div>
  </TeleportWithDirection>
</template>
