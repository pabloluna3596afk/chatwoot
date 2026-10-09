<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';

import Button from 'dashboard/components-next/button/Button.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';
import { useMapGetter } from 'dashboard/composables/store';
import {
  buildLiquidVariables,
  formatLiquidVariable,
} from 'dashboard/helper/liquidVariablesHelper';

const props = defineProps({
  context: {
    type: String,
    default: 'message',
    validator: value => ['message', 'campaign'].includes(value),
  },
  size: {
    type: String,
    default: 'sm',
  },
  // A fixed list of { key, label, description } instead of the message or campaign variables (Captain templates
  // offer the appointment and the assistant ones).
  variables: {
    type: Array,
    default: null,
  },
  showLabel: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['insert']);

const { t, te } = useI18n();
const store = useStore();
const customAttributes = useMapGetter('attributes/getAttributes');
const isOpen = ref(false);

const resolveLabel = variable => {
  const labelKey = `VARIABLES.LABELS.${variable.key}`;
  return te(labelKey) ? t(labelKey) : variable.label;
};

const liquidVariables = computed(
  () =>
    props.variables ||
    buildLiquidVariables(customAttributes.value || [], props.context)
);

const menuItems = computed(() =>
  liquidVariables.value.map(variable => {
    const displayLabel = resolveLabel(variable);
    const liquid = formatLiquidVariable(variable.key);

    return {
      label: `${displayLabel} ${variable.key}`,
      displayLabel,
      description: variable.description || displayLabel,
      liquid,
      value: variable.key,
      action: 'insert',
    };
  })
);

const closeMenu = () => {
  isOpen.value = false;
};

const handleAction = ({ value }) => {
  emit('insert', formatLiquidVariable(value));
  closeMenu();
};

onMounted(() => {
  if (!props.variables && !customAttributes.value?.length) {
    store.dispatch('attributes/get');
  }
});
</script>

<template>
  <MenuPopover
    v-model:open="isOpen"
    :menu-items="menuItems"
    show-search
    :search-placeholder="t('VARIABLES.SEARCH_PLACEHOLDER')"
    panel-class="w-72 [&_button]:!h-auto [&_button]:items-start [&_button]:py-2 max-w-[calc(100vw-2rem)]"
    :restore-focus-on-select="false"
    @action="handleAction"
  >
    <template #trigger>
      <Button
        type="button"
        :size="size"
        variant="ghost"
        color="slate"
        icon="i-lucide-braces"
        :label="showLabel ? t('VARIABLES.INSERT') : ''"
        @click="isOpen = !isOpen"
      />
    </template>

    <template #label="{ item }">
      <div class="flex flex-col min-w-0 flex-1 gap-0.5 text-left">
        <span class="text-sm font-medium text-n-slate-12 truncate">
          {{ item.displayLabel }}
        </span>
        <code class="text-xs text-n-slate-11 truncate">
          {{ item.liquid }}
        </code>
        <span
          v-if="item.description && item.description !== item.displayLabel"
          class="text-xs text-n-slate-10 truncate"
        >
          {{ item.description }}
        </span>
      </div>
    </template>
  </MenuPopover>
</template>
