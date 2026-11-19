<script setup>
import { ref, computed, onMounted, nextTick, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import { useStoreGetters } from 'dashboard/composables/store';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useImageZoom } from 'dashboard/composables/useImageZoom';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import { downloadFile } from '@chatwoot/utils';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import {
  isPdfAttachment,
  PDF_PREVIEW_MAX_BYTES,
} from 'next/message/media/attachment';
import FileIcon from 'next/icon/FileIcon.vue';
import { useMediaState } from 'next/message/media/useMediaState';

import NextButton from 'dashboard/components-next/button/Button.vue';
import Avatar from 'next/avatar/Avatar.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const props = defineProps({
  attachment: {
    type: Object,
    required: true,
  },
  allAttachments: {
    type: Array,
    required: true,
  },
  autoPlay: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close']);
const show = defineModel('show', { type: Boolean, default: false });

const { t } = useI18n();
const getters = useStoreGetters();

const ALLOWED_FILE_TYPES = {
  IMAGE: 'image',
  VIDEO: 'video',
  IG_REEL: 'ig_reel',
  AUDIO: 'audio',
  FILE: 'file',
};

const isDownloading = ref(false);
const activeAttachment = ref({});
const activeFileType = ref('');
const attachmentIndex = props.allAttachments.findIndex(
  attachment => attachment.id === props.attachment.id
);
const activeImageIndex = ref(Math.max(0, attachmentIndex));

const imageRef = useTemplateRef('imageRef');

const {
  imageWrapperStyle,
  imageStyle,
  onRotate,
  activeImageRotation,
  onZoom,
  onDoubleClickZoomImage,
  onWheelImageZoom,
  onMouseMove,
  onMouseLeave,
  resetZoomAndRotation,
} = useImageZoom(imageRef);

const currentUser = computed(() => getters.getCurrentUser.value);
const hasMoreThanOneAttachment = computed(
  () => props.allAttachments.length > 1
);

const readableTime = computed(() => {
  const { created_at: createdAt } = activeAttachment.value;
  if (!createdAt) return '';
  return messageTimestamp(createdAt, 'LLL d yyyy, h:mm a') || '';
});

const isImage = computed(
  () => activeFileType.value === ALLOWED_FILE_TYPES.IMAGE
);
const isVideo = computed(() =>
  [ALLOWED_FILE_TYPES.VIDEO, ALLOWED_FILE_TYPES.IG_REEL].includes(
    activeFileType.value
  )
);
const isAudio = computed(
  () => activeFileType.value === ALLOWED_FILE_TYPES.AUDIO
);

const isFile = computed(() => activeFileType.value === ALLOWED_FILE_TYPES.FILE);
const isPdf = computed(() =>
  isPdfAttachment(useCamelCase(activeAttachment.value))
);
const isPreviewable = computed(
  () => isPdf.value && activeAttachment.value.file_size <= PDF_PREVIEW_MAX_BYTES
);
const focusBeforeOpen = document.activeElement;
const closeButton = useTemplateRef('closeButton');
const { isLoaded, hasError, errorText, onLoad, onError } = useMediaState(() =>
  useCamelCase(activeAttachment.value)
);

const retryPreview = () => {
  hasError.value = false;
  isLoaded.value = false;
};

const senderDetails = computed(() => {
  const {
    name,
    available_name: availableName,
    avatar_url,
    thumbnail,
    id,
  } = activeAttachment.value?.sender || props.attachment?.sender || {};

  return {
    name: currentUser.value?.id === id ? 'You' : name || availableName || '',
    avatar: thumbnail || avatar_url || '',
  };
});

const fileNameFromDataUrl = computed(() => {
  const { data_url: dataUrl } = activeAttachment.value;
  if (!dataUrl) return '';

  const fileName = dataUrl.split('/').pop();
  return fileName ? decodeURIComponent(fileName) : '';
});

const onClose = () => {
  emit('close');
  focusBeforeOpen?.focus();
};

const setImageAndVideoSrc = attachment => {
  const { file_type: type } = attachment;
  if (!Object.values(ALLOWED_FILE_TYPES).includes(type)) return;

  activeAttachment.value = attachment;
  activeFileType.value = type;
};

const onClickChangeAttachment = (attachment, index) => {
  if (!attachment) return;

  activeImageIndex.value = index;
  setImageAndVideoSrc(attachment);
  resetZoomAndRotation();
};

const onClickDownload = async () => {
  const { file_type: type, data_url: url, extension } = activeAttachment.value;
  if (!Object.values(ALLOWED_FILE_TYPES).includes(type)) return;

  try {
    isDownloading.value = true;
    await downloadFile({ url, type, extension });
  } catch (error) {
    useAlert(t('GALLERY_VIEW.ERROR_DOWNLOADING'));
  } finally {
    isDownloading.value = false;
  }
};

const keyboardEvents = {
  Escape: { action: onClose },
  ArrowLeft: {
    action: () => {
      onClickChangeAttachment(
        props.allAttachments[activeImageIndex.value - 1],
        activeImageIndex.value - 1
      );
    },
  },
  ArrowRight: {
    action: () => {
      onClickChangeAttachment(
        props.allAttachments[activeImageIndex.value + 1],
        activeImageIndex.value + 1
      );
    },
  },
};

useKeyboardEvents(keyboardEvents);

onMounted(async () => {
  setImageAndVideoSrc(props.attachment);
  await nextTick();
  closeButton.value?.$el?.focus();
});
</script>

<template>
  <TeleportWithDirection to="body">
    <woot-modal
      v-model:show="show"
      full-width
      :show-close-button="false"
      :on-close="onClose"
    >
      <div
        class="bg-n-background flex flex-col h-[inherit] w-[inherit] overflow-hidden select-none"
        @click="onClose"
      >
        <header
          class="z-10 flex flex-wrap items-center justify-between gap-2 w-full min-h-16 px-3 py-2 bg-n-background border-b border-n-weak"
          @click.stop
        >
          <div
            v-if="senderDetails"
            class="hidden md:flex items-center min-w-0 shrink-0"
          >
            <Avatar
              v-if="senderDetails.avatar"
              :name="senderDetails.name"
              :src="senderDetails.avatar"
              :size="40"
              rounded-full
              class="flex-shrink-0"
            />
            <div class="flex flex-col ms-2 overflow-hidden">
              <h3 class="text-base leading-5 m-0 font-medium">
                <span
                  class="overflow-hidden text-n-slate-12 whitespace-nowrap text-ellipsis"
                >
                  {{ senderDetails.name }}
                </span>
              </h3>
              <span
                class="text-xs text-n-slate-11 whitespace-nowrap text-ellipsis"
              >
                {{ readableTime }}
              </span>
            </div>
          </div>

          <div
            class="min-w-0 flex-1 mx-2 px-2 truncate text-sm font-medium text-center text-n-slate-12"
          >
            <span v-dompurify-html="fileNameFromDataUrl" class="truncate" />
          </div>

          <div class="flex flex-wrap items-center gap-1 ms-auto shrink-0">
            <span class="text-xs text-n-slate-11">{{
              t('GALLERY_VIEW.COUNTER', {
                index: activeImageIndex + 1,
                total: allAttachments.length,
              })
            }}</span>
            <a
              :href="activeAttachment.data_url"
              target="_blank"
              rel="noopener noreferrer"
              class="flex items-center gap-1.5 rounded-lg px-2 py-2 text-xs text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            >
              <span class="i-lucide-external-link" aria-hidden="true" />
              {{ t('GALLERY_VIEW.OPEN_ORIGINAL') }}
            </a>
            <NextButton
              v-if="isImage"
              icon="i-lucide-zoom-in"
              intent="tertiary"
              :aria-label="t('GALLERY_VIEW.ZOOM_IN')"
              @click="onZoom(0.1)"
            />
            <NextButton
              v-if="isImage"
              icon="i-lucide-zoom-out"
              intent="tertiary"
              :aria-label="t('GALLERY_VIEW.ZOOM_OUT')"
              @click="onZoom(-0.1)"
            />
            <NextButton
              v-if="isImage"
              icon="i-lucide-rotate-ccw"
              intent="tertiary"
              :aria-label="t('GALLERY_VIEW.ROTATE_LEFT')"
              @click="onRotate('counter-clockwise')"
            />
            <NextButton
              v-if="isImage"
              icon="i-lucide-rotate-cw"
              intent="tertiary"
              :aria-label="t('GALLERY_VIEW.ROTATE_RIGHT')"
              @click="onRotate('clockwise')"
            />
            <NextButton
              icon="i-lucide-download"
              intent="secondary"
              :aria-label="t('CONVERSATION.DOWNLOAD')"
              :is-loading="isDownloading"
              :disabled="isDownloading"
              @click="onClickDownload"
            />
            <NextButton
              ref="closeButton"
              icon="i-lucide-x"
              intent="tertiary"
              :aria-label="t('GALLERY_VIEW.CLOSE')"
              @click="onClose"
            />
          </div>
        </header>

        <main
          class="flex items-stretch flex-1 min-h-0 overflow-hidden bg-n-alpha-1"
        >
          <div class="flex items-center justify-center w-8 md:w-16 shrink-0">
            <NextButton
              v-if="hasMoreThanOneAttachment"
              icon="ltr:i-lucide-chevron-left rtl:i-lucide-chevron-right"
              class="z-10"
              blue
              faded
              lg
              :disabled="activeImageIndex === 0"
              @click.stop="
                onClickChangeAttachment(
                  allAttachments[activeImageIndex - 1],
                  activeImageIndex - 1
                )
              "
            />
          </div>

          <div
            class="relative flex-1 min-w-0 flex items-center justify-center overflow-hidden"
          >
            <div
              v-if="hasError"
              role="status"
              class="flex flex-col items-center gap-3 p-6 text-center text-n-slate-11"
              @click.stop
            >
              <span class="i-lucide-image-off size-8" aria-hidden="true" />
              <p class="m-0 text-sm">{{ errorText }}</p>
              <NextButton
                intent="secondary"
                :label="t('COMPONENTS.MEDIA.RETRY')"
                @click="retryPreview"
              />
            </div>
            <span
              v-else-if="!isLoaded && (isImage || isVideo || isAudio)"
              class="absolute size-8 i-lucide-loader-circle animate-spin motion-reduce:animate-none text-n-slate-11"
              aria-hidden="true"
            />
            <div
              v-if="isImage && !hasError"
              :style="imageWrapperStyle"
              class="flex items-center justify-center origin-center"
              :class="{
                // Adjust dimensions when rotated 90/270 degrees to maintain visibility
                // and prevent image from overflowing container in different aspect ratios
                'w-[calc(100dvh-8rem)] h-[calc(100dvw-7rem)]':
                  activeImageRotation % 180 !== 0,
                'size-full': activeImageRotation % 180 === 0,
              }"
            >
              <img
                ref="imageRef"
                :key="activeAttachment.id"
                :src="activeAttachment.data_url"
                :alt="fileNameFromDataUrl"
                :style="imageStyle"
                class="max-h-full max-w-full object-contain duration-100 ease-in-out transform select-none motion-reduce:transition-none"
                @click.stop
                @load="onLoad"
                @error="onError"
                @dblclick.stop="onDoubleClickZoomImage"
                @wheel.prevent.stop="onWheelImageZoom"
                @mousemove="onMouseMove"
                @mouseleave="onMouseLeave"
              />
            </div>

            <iframe
              v-if="isPreviewable"
              :key="activeAttachment.id"
              :src="activeAttachment.data_url"
              :title="fileNameFromDataUrl"
              class="w-full max-w-[60rem] h-full my-2 rounded-lg bg-white"
              referrerpolicy="no-referrer"
              @click.stop
            />
            <div
              v-else-if="isFile"
              class="flex flex-col items-center gap-3 p-4 text-center text-n-slate-12"
              @click.stop
            >
              <FileIcon
                :file-type="activeAttachment.extension || ''"
                class="size-9"
              />
              <span class="break-all">{{ fileNameFromDataUrl }}</span>
              <p v-if="isPdf">{{ t('GALLERY_VIEW.PDF_TOO_LARGE') }}</p>
              <NextButton
                intent="secondary"
                :label="t('CONVERSATION.DOWNLOAD')"
                :is-loading="isDownloading"
                @click="onClickDownload"
              />
            </div>
            <video
              v-if="isVideo && !hasError"
              :key="activeAttachment.id"
              :src="activeAttachment.data_url"
              controls
              playsInline
              :autoplay="autoPlay"
              class="max-h-full max-w-full object-contain"
              @loadeddata="onLoad"
              @error="onError"
              @click.stop
            />

            <audio
              v-if="isAudio && !hasError"
              :key="activeAttachment.id"
              controls
              :autoplay="autoPlay"
              class="w-full max-w-md"
              @loadeddata="onLoad"
              @error="onError"
              @click.stop
            >
              <source :src="`${activeAttachment.data_url}?t=${Date.now()}`" />
            </audio>
          </div>

          <div class="flex items-center justify-center w-8 md:w-16 shrink-0">
            <NextButton
              v-if="hasMoreThanOneAttachment"
              icon="ltr:i-lucide-chevron-right rtl:i-lucide-chevron-left"
              class="z-10"
              blue
              faded
              lg
              :disabled="activeImageIndex === allAttachments.length - 1"
              @click.stop="
                onClickChangeAttachment(
                  allAttachments[activeImageIndex + 1],
                  activeImageIndex + 1
                )
              "
            />
          </div>
        </main>
      </div>
    </woot-modal>
  </TeleportWithDirection>
</template>
