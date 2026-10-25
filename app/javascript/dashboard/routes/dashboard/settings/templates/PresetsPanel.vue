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
      <p class="mt-1 text-body-main text-n-slate-11">
        {{ $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.DESCRIPTION') }}
      </p>
    </div>

    <PresetPicker
      :items="presets"
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
            <p>
              {{
                $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.VARIABLES', {
                  variables: item.variables.join(', '),
                })
              }}
            </p>
            <p class="mt-2">
              {{
                $t(
                  `WHATSAPP_TEMPLATE_MGMT.PRESETS.CATEGORY_NOTE.${item.category}`
                )
              }}
            </p>
            <p v-if="item.disabled" class="mt-2 text-n-amber-11">
              {{ $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.DISABLED_FORMS') }}
            </p>
          </template>
          <template #actions>
            <Button
              :label="item.actionLabel"
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
      @created="emit('created')"
    />
  </div>
</template>
