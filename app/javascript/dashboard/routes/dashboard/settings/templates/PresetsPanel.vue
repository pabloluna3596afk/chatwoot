<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import PresetCard from 'dashboard/components-next/preset/PresetCard.vue';
import PresetPicker from 'dashboard/components-next/preset/PresetPicker.vue';
import LibraryPanel from './LibraryPanel.vue';
import { PRESETS, PRESET_GROUPS } from './presets';
import { variableTokens } from './templateForm';

defineProps({
  // The WhatsApp Cloud inboxes a template can be created in.
  inboxes: { type: Array, default: () => [] },
  templates: { type: Array, default: () => [] },
  search: { type: String, default: '' },
});

const emit = defineEmits(['use', 'created']);
const { t } = useI18n();

const groups = computed(() =>
  PRESET_GROUPS.map(id => ({
    id,
    label: t(`WHATSAPP_TEMPLATE_MGMT.PRESETS.GROUPS.${id}`),
  }))
);

const presets = computed(() =>
  PRESETS.map(preset => ({
    ...preset,
    title: t(`WHATSAPP_TEMPLATE_MGMT.PRESETS.ITEMS.${preset.id}.TITLE`),
    description: t(
      `WHATSAPP_TEMPLATE_MGMT.PRESETS.ITEMS.${preset.id}.DESCRIPTION`
    ),
    tags: [
      {
        label: t(
          `WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORIES.${preset.category}.LABEL`
        ),
        color: preset.category === 'UTILITY' ? 'teal' : 'amber',
      },
    ],
    actionLabel: t('WHATSAPP_TEMPLATE_MGMT.PRESETS.USE'),
    actionIcon: 'i-lucide-wand-sparkles',
    variables: variableTokens(preset.body),
  }))
);
</script>

<template>
  <div class="flex flex-col gap-8" data-testid="presets-panel">
    <div>
      <h2 class="text-heading-2 text-n-slate-12">
        {{ $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.TITLE') }}
      </h2>
      <p class="mb-0 mt-1 text-body-main text-n-slate-11">
        {{ $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.DESCRIPTION') }}
      </p>
      <div
        class="mt-1 flex flex-wrap gap-1.5 text-xs text-n-slate-11"
        data-testid="category-help"
      >
        <span
          class="inline-flex max-w-full items-center gap-1 rounded-md bg-n-alpha-1 px-1 py-0.5"
          data-testid="category-chip"
        >
          <span class="shrink-0 rounded bg-n-teal-3 px-1 text-n-teal-11">{{
            $t('WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORIES.UTILITY.LABEL')
          }}</span>
          {{ $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.CATEGORY_NOTE.UTILITY') }}
        </span>
        <span
          class="inline-flex max-w-full items-center gap-1 rounded-md bg-n-alpha-1 px-1 py-0.5"
          data-testid="category-chip"
        >
          <span class="shrink-0 rounded bg-n-amber-3 px-1 text-n-amber-11">{{
            $t('WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORIES.MARKETING.LABEL')
          }}</span>
          {{ $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.CATEGORY_NOTE.MARKETING') }}
        </span>
      </div>
    </div>
    <PresetPicker
      :items="presets"
      :search-query="search"
      :groups="groups"
      :columns="2"
      @apply="preset => emit('use', preset)"
    >
      <template #card="{ item, apply }">
        <PresetCard
          :id="item.id"
          :title="item.title"
          :description="item.description"
          :tags="item.tags"
          :action-label="item.actionLabel"
          :action-icon="item.actionIcon"
          :disabled="item.disabled"
          @apply="apply"
        >
          <template #preview>
            <p class="rounded-lg bg-n-alpha-2 p-2 text-xs">
              {{ item.body }}
            </p>
          </template>
          <template #meta>
            <p class="text-xs text-n-slate-10">
              {{
                $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.VARIABLES', {
                  variables: item.variables.join(', '),
                })
              }}
            </p>
            <p v-if="item.disabled" class="mt-2 text-xs text-n-amber-11">
              {{ $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.DISABLED_FORMS') }}
            </p>
          </template>
          <template #actions>
            <Button
              :label="item.actionLabel"
              :aria-label="`${item.actionLabel}: ${item.title}`"
              :icon="item.actionIcon"
              size="sm"
              intent="primary"
              :disabled="item.disabled"
              :data-testid="`use-${item.id}`"
              @click="apply"
            />
          </template>
        </PresetCard>
      </template>
    </PresetPicker>

    <LibraryPanel
      :inboxes="inboxes"
      :templates="templates"
      @created="draft => emit('created', draft)"
    />
  </div>
</template>
