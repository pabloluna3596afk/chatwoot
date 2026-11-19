<script setup>
import { nextTick, ref, watch } from 'vue';
import { useMediaQuery } from '@vueuse/core';
import { showModal } from 'dashboard/helper/overlayFocus';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import MenuItem from 'dashboard/components-next/dropdown-menu/MenuItem.vue';

const props = defineProps({ items: { type: Array, required: true } });
const emit = defineEmits(['select']);
const isPhone = useMediaQuery('(max-width: 767px)');
const isOpen = ref(false);
const trigger = ref(null);
const dialog = ref(null);
const popover = ref(null);
const menu = ref(null);

const close = async () => {
  dialog.value?.close();
  popover.value?.hide();
  isOpen.value = false;
  await nextTick();
  trigger.value?.$el?.focus({ preventScroll: true });
};
const open = async () => {
  isOpen.value = true;
  await nextTick();
  if (isPhone.value) showModal(dialog.value);
  else menu.value?.querySelector('button:enabled')?.focus();
};
const select = async item => {
  await close();
  emit('select', item.key);
};
const navigate = event => {
  const buttons = [...event.currentTarget.querySelectorAll('button:enabled')];
  const index = buttons.indexOf(document.activeElement);
  const directions = { ArrowDown: 1, ArrowUp: -1 };
  if (event.key in directions) {
    event.preventDefault();
    buttons[
      (index + directions[event.key] + buttons.length) % buttons.length
    ]?.focus();
  } else if (event.key === 'Home' || event.key === 'End') {
    event.preventDefault();
    buttons[event.key === 'Home' ? 0 : buttons.length - 1]?.focus();
  }
};
watch(isPhone, close);
watch(
  () => props.items.length,
  length => {
    if (!length) close();
  }
);
</script>

<template>
  <div class="shrink-0" @keydown.esc.stop.prevent="close">
    <NextButton
      v-if="isPhone"
      ref="trigger"
      intent="tertiary"
      sm
      icon="i-lucide-ellipsis"
      :aria-label="$t('CONVERSATION.REPLYBOX.MORE_OPTIONS')"
      aria-haspopup="menu"
      :aria-expanded="isOpen"
      @click="open"
    />
    <Popover
      v-else
      ref="popover"
      disable-mobile-view
      :aria-label="$t('CONVERSATION.REPLYBOX.MORE_OPTIONS')"
      @show="open"
      @hide="isOpen = false"
    >
      <NextButton
        ref="trigger"
        intent="tertiary"
        sm
        icon="i-lucide-ellipsis"
        :aria-label="$t('CONVERSATION.REPLYBOX.MORE_OPTIONS')"
        aria-haspopup="menu"
        :aria-expanded="isOpen"
      />
      <template #content>
        <div
          ref="menu"
          role="menu"
          :aria-label="$t('CONVERSATION.REPLYBOX.MORE_OPTIONS')"
          class="min-w-[15rem] p-1.5"
          @keydown="navigate"
          @keydown.esc.stop.prevent="close"
        >
          <MenuItem
            v-for="item in items"
            :key="item.key"
            role="menuitem"
            :disabled="item.disabled"
            @click="select(item)"
          >
            <Icon :icon="item.icon" class="size-4 shrink-0" />
            <span>{{ item.label }}</span>
            <span v-if="item.state" class="ms-auto text-xs text-n-slate-11">{{
              item.state
            }}</span>
          </MenuItem>
        </div>
      </template>
    </Popover>
    <Teleport to="body">
      <dialog
        v-if="isPhone && isOpen"
        ref="dialog"
        :aria-label="$t('CONVERSATION.REPLYBOX.MORE_OPTIONS')"
        class="fixed inset-x-0 bottom-0 top-auto m-0 w-full max-w-none max-h-[80dvh] rounded-t-2xl border-0 bg-n-surface-1 p-2 pb-[max(0.5rem,env(safe-area-inset-bottom))] text-n-slate-12 shadow-xl backdrop:bg-n-alpha-black1"
        @cancel.prevent="close"
        @close="isOpen = false"
        @keydown.esc.stop.prevent="close"
      >
        <div
          role="menu"
          :aria-label="$t('CONVERSATION.REPLYBOX.MORE_OPTIONS')"
          @keydown="navigate"
        >
          <MenuItem
            v-for="item in items"
            :key="item.key"
            role="menuitem"
            :disabled="item.disabled"
            class="!h-11"
            @click="select(item)"
          >
            <Icon :icon="item.icon" class="size-4 shrink-0" />
            <span>{{ item.label }}</span>
            <span v-if="item.state" class="ms-auto text-xs text-n-slate-11">{{
              item.state
            }}</span>
          </MenuItem>
        </div>
      </dialog>
    </Teleport>
  </div>
</template>
