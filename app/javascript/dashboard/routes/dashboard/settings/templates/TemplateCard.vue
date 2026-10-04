<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import {
  formatTemplateLabel,
  formatTemplateLanguage,
  templateStatusClasses,
  templateTypeKey,
} from './templateUtils';

const props = defineProps({
  template: {
    type: Object,
    required: true,
  },
  // Administrators of a WhatsApp Cloud template can edit and delete it from here.
  canManage: {
    type: Boolean,
    default: false,
  },
  canEdit: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['preview', 'edit', 'delete']);
const { t, te } = useI18n();

const showStatus = computed(
  () => props.template.status?.toLowerCase() !== 'approved'
);
const statusKey = computed(() =>
  String(props.template.status || '').toUpperCase()
);
const statusLabel = computed(() => {
  if (props.template.status?.toLowerCase() === 'unsubmitted')
    return t('WHATSAPP_TEMPLATE_MGMT.STATUSES.UNSUBMITTED');
  return te(`WHATSAPP_TEMPLATE_MGMT.STATUS.${statusKey.value}`)
    ? t(`WHATSAPP_TEMPLATE_MGMT.STATUS.${statusKey.value}`)
    : formatTemplateLabel(props.template.status);
});
</script>

<template>
  <div
    class="flex items-center justify-between gap-4 py-4 cursor-pointer group"
    role="button"
    tabindex="0"
    @click="emit('preview')"
    @keydown.enter="emit('preview')"
    @keydown.space.prevent="emit('preview')"
  >
    <div class="flex items-center min-w-0 gap-3">
      <span
        class="grid border rounded-xl shadow-sm size-10 shrink-0 place-items-center bg-n-alpha-3 border-n-strong ring ring-n-solid-1"
      >
        <ChannelIcon
          :inbox="template.inboxes[0]"
          class="size-5 text-n-slate-11"
        />
      </span>
      <div class="flex flex-col min-w-0 gap-1">
        <div class="flex items-center min-w-0 gap-2">
          <span class="truncate text-heading-3 text-n-slate-12">
            {{ template.name }}
          </span>
          <span
            v-if="showStatus"
            class="inline-flex shrink-0 px-2 py-0.5 text-xs font-medium rounded-md"
            :class="templateStatusClasses(template.status)"
          >
            {{ statusLabel }}
          </span>
        </div>
        <div
          class="flex flex-wrap items-center gap-2 text-body-main text-n-slate-11"
        >
          <span>
            {{
              $t(`WHATSAPP_TEMPLATE_MGMT.TYPES.${templateTypeKey(template)}`)
            }}
          </span>
          <div class="w-px h-3 rounded-lg bg-n-strong" />
          <span>{{ formatTemplateLanguage(template.language) }}</span>
          <div class="w-px h-3 rounded-lg bg-n-strong" />
          <span class="truncate">{{ template.inboxNames }}</span>
        </div>
      </div>
    </div>
    <div class="flex items-center gap-1 shrink-0">
      <Button
        v-if="canManage && canEdit"
        v-tooltip.top="$t('WHATSAPP_TEMPLATE_MGMT.EDIT')"
        icon="i-lucide-pencil"
        color="slate"
        size="sm"
        data-testid="template-edit"
        :aria-label="$t('WHATSAPP_TEMPLATE_MGMT.EDIT')"
        @click.stop="emit('edit')"
      />
      <Button
        v-if="canManage"
        v-tooltip.top="$t('WHATSAPP_TEMPLATE_MGMT.DELETE')"
        icon="i-lucide-trash-2"
        color="ruby"
        size="sm"
        data-testid="template-delete"
        :aria-label="$t('WHATSAPP_TEMPLATE_MGMT.DELETE')"
        @click.stop="emit('delete')"
      />
      <Button
        v-tooltip.top="$t('WHATSAPP_TEMPLATE_MGMT.PREVIEW.TITLE')"
        icon="i-lucide-eye"
        color="slate"
        size="sm"
        :aria-label="
          $t('WHATSAPP_TEMPLATE_MGMT.PREVIEW.OPEN', { name: template.name })
        "
        @click.stop="emit('preview')"
      />
    </div>
  </div>
</template>
