<script setup>
import { computed } from 'vue';

import Button from 'dashboard/components-next/button/Button.vue';
import LibraryPanel from './LibraryPanel.vue';
import { PRESETS, PRESET_GROUPS } from './presets';
import { variableTokens } from './templateForm';

defineProps({
  // The WhatsApp Cloud inboxes a template can be created in.
  inboxes: { type: Array, default: () => [] },
  templates: { type: Array, default: () => [] },
});

const emit = defineEmits(['use', 'created']);

const grouped = computed(() =>
  PRESET_GROUPS.map(group => ({
    group,
    presets: PRESETS.filter(preset => preset.group === group).map(preset => ({
      ...preset,
      variables: variableTokens(preset.body),
    })),
  })).filter(section => section.presets.length)
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

    <section v-for="section in grouped" :key="section.group" class="grid gap-3">
      <h3 class="text-sm font-medium text-n-slate-12">
        {{ $t(`WHATSAPP_TEMPLATE_MGMT.PRESETS.GROUPS.${section.group}`) }}
      </h3>
      <div class="grid gap-3 sm:grid-cols-2">
        <article
          v-for="preset in section.presets"
          :key="preset.id"
          class="flex flex-col gap-2 p-4 border rounded-xl border-n-weak"
          :class="{ 'opacity-60': preset.disabled }"
          :data-testid="`preset-${preset.id}`"
        >
          <div class="flex items-start justify-between gap-2">
            <h4 class="text-heading-3 text-n-slate-12">
              {{
                $t(`WHATSAPP_TEMPLATE_MGMT.PRESETS.ITEMS.${preset.id}.TITLE`)
              }}
            </h4>
            <span
              class="inline-flex shrink-0 px-2 py-0.5 text-xs font-medium rounded-md"
              :class="
                preset.category === 'UTILITY'
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-amber-3 text-n-amber-11'
              "
            >
              {{
                $t(
                  `WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORIES.${preset.category}.LABEL`
                )
              }}
            </span>
          </div>
          <p class="text-body-main text-n-slate-11">
            {{
              $t(
                `WHATSAPP_TEMPLATE_MGMT.PRESETS.ITEMS.${preset.id}.DESCRIPTION`
              )
            }}
          </p>
          <p class="p-2 text-xs rounded-lg text-n-slate-12 bg-n-alpha-2">
            {{ preset.body }}
          </p>
          <p class="text-xs text-n-slate-10">
            {{
              $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.VARIABLES', {
                variables: preset.variables.join(', '),
              })
            }}
          </p>
          <p class="text-xs text-n-slate-10">
            {{
              $t(
                `WHATSAPP_TEMPLATE_MGMT.PRESETS.CATEGORY_NOTE.${preset.category}`
              )
            }}
          </p>
          <p v-if="preset.disabled" class="text-xs text-n-amber-11">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.DISABLED_FORMS') }}
          </p>
          <div class="mt-auto">
            <Button
              :label="$t('WHATSAPP_TEMPLATE_MGMT.PRESETS.USE')"
              icon="i-lucide-wand-sparkles"
              size="sm"
              :disabled="preset.disabled"
              :data-testid="`use-${preset.id}`"
              @click="emit('use', preset)"
            />
          </div>
        </article>
      </div>
    </section>

    <LibraryPanel
      :inboxes="inboxes"
      :templates="templates"
      @created="emit('created')"
    />
  </div>
</template>
