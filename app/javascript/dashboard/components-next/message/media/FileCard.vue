<script setup>
import { computed, shallowRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { downloadFile } from '@chatwoot/utils';
import { useMapGetter } from 'dashboard/composables/store';
import {
  useCamelCase,
  useSnakeCase,
} from 'dashboard/composables/useTransformKeys';
import FileIcon from 'next/icon/FileIcon.vue';
import Button from 'next/button/Button.vue';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import {
  attachmentName,
  attachmentExtension,
  isPdfAttachment,
  middleEllipsis,
  PDF_PREVIEW_MAX_BYTES,
  downloadAttachment,
} from './attachment';
import { useMediaState } from './useMediaState';

const props = defineProps({
  attachment: { type: Object, required: true },
  channelType: { type: String, default: '' },
});
const { t, locale } = useI18n();
const chatAttachments = useMapGetter('getSelectedChatAttachments');
const showGallery = shallowRef(false);
const isDownloading = shallowRef(false);
const name = computed(
  () => attachmentName(props.attachment) || t('CONVERSATION.UNKNOWN_FILE_TYPE')
);
const extension = computed(() => attachmentExtension(props.attachment));
const type = computed(() => {
  const types = {
    pdf: 'PDF',
    doc: 'WORD',
    docx: 'WORD',
    odt: 'WORD',
    xls: 'EXCEL',
    xlsx: 'EXCEL',
    csv: 'EXCEL',
    ppt: 'POWERPOINT',
    pptx: 'POWERPOINT',
    zip: 'ZIP',
    rar: 'ZIP',
    '7z': 'ZIP',
    txt: 'TEXT',
  };
  return t(`COMPONENTS.FILE.TYPE.${types[extension.value] || 'FILE'}`);
});
const size = computed(() => {
  if (props.attachment.fileSize == null) return '';
  if (props.attachment.fileSize < 1024) return `${props.attachment.fileSize} B`;
  const megabytes = props.attachment.fileSize >= 1024 * 1024;
  const value = props.attachment.fileSize / (megabytes ? 1024 * 1024 : 1024);
  return `${new Intl.NumberFormat(locale.value, { minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(value)} ${megabytes ? 'MB' : 'KB'}`;
});
const canPreview = computed(
  () =>
    props.attachment.fileType === 'image' ||
    (isPdfAttachment(props.attachment) &&
      props.attachment.fileSize <= PDF_PREVIEW_MAX_BYTES)
);
const galleryAttachments = computed(() => {
  // Search results also use FileCard, outside the selected conversation.
  const items = chatAttachments.value.filter(
    item =>
      ['image', 'video', 'ig_reel', 'audio'].includes(item.file_type) ||
      isPdfAttachment(useCamelCase(item))
  );
  return items.some(item => item.id === props.attachment.id)
    ? items
    : [useSnakeCase(props.attachment)];
});
const { isExpired, errorText, onError } = useMediaState(
  () => props.attachment,
  () => props.channelType
);
const download = async () => {
  isDownloading.value = true;
  if (!(await downloadAttachment(props.attachment, downloadFile))) onError();
  isDownloading.value = false;
};
</script>

<template>
  <div
    class="flex items-center gap-2.5 p-2 rounded-xl border border-n-weak bg-n-surface-1 min-w-0 w-[min(20rem,100%)]"
    @click.stop
  >
    <FileIcon :file-type="extension" class="size-9 shrink-0 text-n-slate-12" />
    <div class="min-w-0 flex-1">
      <div
        class="line-clamp-2 break-words text-sm font-medium text-n-slate-12"
        :title="name"
      >
        {{ middleEllipsis(name) }}
      </div>
      <div class="text-xs text-n-slate-11">
        {{ size ? `${type} \u00b7 ${size}` : type }}
      </div>
      <div v-if="isExpired" role="status" class="text-xs text-n-slate-11">
        {{ errorText }}
      </div>
    </div>
    <Button
      v-if="canPreview"
      size="xs"
      intent="primary"
      :label="t('COMPONENTS.FILE.VIEW')"
      @click.prevent="showGallery = true"
    />
    <Button
      size="xs"
      intent="tertiary"
      icon="i-lucide-download"
      :aria-label="t('CONVERSATION.DOWNLOAD')"
      :is-loading="isDownloading"
      :disabled="isDownloading"
      @click.prevent="download"
    />
  </div>
  <GalleryView
    v-if="showGallery"
    show
    :attachment="useSnakeCase(attachment)"
    :all-attachments="galleryAttachments"
    @close="showGallery = false"
  />
</template>
