<script setup>
import { useI18n } from 'vue-i18n';
import CardLayout from '../CardLayout.vue';
import MenuPopover from '../dropdown-menu/MenuPopover.vue';
import Button from '../button/Button.vue';

defineProps({
  title: { type: String, required: true },
  subtitle: { type: String, default: '' },
  menuItems: { type: Array, default: () => [] },
});
const emit = defineEmits(['action']);
const { t } = useI18n();
</script>

<template>
  <CardLayout
    padding="compact"
    class="min-w-0 dark:bg-n-solid-3"
    data-list-card
  >
    <div
      class="grid w-full min-w-0 grid-cols-[auto_minmax(0,1fr)_auto] items-start gap-3 md:grid-cols-[auto_minmax(0,1fr)_18rem_auto] md:items-center"
    >
      <div class="shrink-0"><slot name="avatar" /></div>
      <div class="min-w-0">
        <h3 :title="title" class="m-0 truncate text-heading-3 text-n-slate-12">
          {{ title }}
        </h3>
        <p
          v-if="subtitle"
          :title="subtitle"
          class="m-0 truncate text-body-main text-n-slate-11"
        >
          {{ subtitle }}
        </p>
      </div>
      <div
        class="col-span-3 row-start-2 flex min-w-0 flex-wrap items-center justify-start gap-1.5 md:col-span-1 md:col-start-3 md:row-start-1 md:w-72 md:shrink-0"
        data-list-chips
      >
        <slot name="chips" />
      </div>
      <MenuPopover
        class="col-start-3 row-start-1 shrink-0 -mt-2 md:col-start-4 md:mt-0"
        :menu-items="menuItems"
        :label="t('CONVERSATION.HEADER.MORE_ACTIONS')"
        panel-class="w-56 max-w-[calc(100vw-2rem)] !bg-n-solid-3 shadow-lg"
        @action="emit('action', $event)"
      >
        <template #trigger="{ open, toggle }">
          <Button
            icon="i-lucide-ellipsis-vertical"
            color="slate"
            variant="ghost"
            size="sm"
            class="size-11 min-h-11 min-w-11"
            :aria-label="`${t('CONVERSATION.HEADER.MORE_ACTIONS')}: ${title}`"
            aria-haspopup="dialog"
            :aria-expanded="open"
            :disabled="!menuItems.length"
            @click="toggle"
          />
        </template>
      </MenuPopover>
    </div>
    <template #after><slot name="after" /></template>
  </CardLayout>
</template>
