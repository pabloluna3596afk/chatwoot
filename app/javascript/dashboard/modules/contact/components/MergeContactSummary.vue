<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { escapeHtml } from 'shared/helpers/HTMLSanitizer';

const props = defineProps({
  primaryContactName: { type: String, default: '' },
  parentContactName: { type: String, default: '' },
});
const { t } = useI18n();
const deleteWarning = computed(() =>
  t('MERGE_CONTACTS.SUMMARY.DELETE_WARNING', {
    primaryContactName: escapeHtml(props.primaryContactName || ''),
  })
);
const attributeWarning = computed(() =>
  t('MERGE_CONTACTS.SUMMARY.ATTRIBUTE_WARNING', {
    primaryContactName: escapeHtml(props.primaryContactName || ''),
    parentContactName: escapeHtml(props.parentContactName),
  })
);
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div
    v-if="parentContactName"
    class="my-4 relative p-2.5 border rounded-[4px] text-n-slate-12 border-n-weak bg-n-background"
  >
    <h5 class="text-base font-medium text-n-slate-12">
      {{ $t('MERGE_CONTACTS.SUMMARY.TITLE') }}
    </h5>
    <ul class="ml-0 list-none">
      <li>
        <span class="inline-block mr-1">❌</span>
        <span v-dompurify-html="deleteWarning" />
      </li>
      <li>
        <span class="inline-block mr-1">✅</span>
        <span v-dompurify-html="attributeWarning" />
      </li>
    </ul>
  </div>
</template>
