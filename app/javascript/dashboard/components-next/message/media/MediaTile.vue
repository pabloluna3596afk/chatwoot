<script setup>
import { computed, shallowRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { downloadFile } from '@chatwoot/utils';
import Button from 'next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import { attachmentName, downloadAttachment } from './attachment';
import { useMediaState } from './useMediaState';

const props = defineProps({
  attachment: { type: Object, required: true },
  caption: { type: String, default: '' },
  index: { type: Number, required: true },
  total: { type: Number, required: true },
  more: { type: Number, default: 0 },
  channelType: { type: String, default: '' },
});
const emit = defineEmits(['open']);
const { t } = useI18n();
const single = computed(() => props.total === 1);
const isVideo = computed(() =>
  ['video', 'ig_reel'].includes(props.attachment.fileType)
);
const loadedDimensions = shallowRef(null);
const dimensions = computed(() => ({
  width: props.attachment.width || loadedDimensions.value?.width,
  height: props.attachment.height || loadedDimensions.value?.height,
}));
const tall = computed(
  () => single.value && dimensions.value.height / dimensions.value.width > 3
);
const tiny = computed(
  () =>
    single.value &&
    dimensions.value.width > 0 &&
    dimensions.value.height > 0 &&
    Math.max(dimensions.value.width, dimensions.value.height) < 120
);
const src = computed(() =>
  single.value && !isVideo.value
    ? props.attachment.dataUrl
    : props.attachment.thumbUrl || props.attachment.dataUrl
);
const alt = computed(
  () =>
    props.caption ||
    attachmentName(props.attachment) ||
    t('CONVERSATION.REPLY_PREVIEW.PHOTO')
);
const label = computed(() =>
  t('COMPONENTS.MEDIA.PHOTO_N_OF', {
    index: props.index + 1,
    total: props.total,
  })
);
const { isLoaded, hasError, isExpired, errorText, onLoad, onError, retry } =
  useMediaState(
    () => props.attachment,
    () => props.channelType,
    src
  );
const handleLoad = event => {
  loadedDimensions.value = {
    width: event.target.naturalWidth,
    height: event.target.naturalHeight,
  };
  onLoad();
};
const isDownloading = shallowRef(false);
const download = async () => {
  isDownloading.value = true;
  await downloadAttachment(props.attachment, downloadFile);
  isDownloading.value = false;
};
</script>

<template>
  <figure
    class="relative group overflow-hidden bg-n-alpha-1 m-0 min-w-0"
    :class="[
      single ? 'rounded-lg max-w-[20rem] max-h-[22rem] w-full' : 'h-full',
      {
        'row-span-2': total === 3 && index === 0,
        'p-3 grid place-items-center': tiny,
      },
    ]"
  >
    <button
      type="button"
      class="relative block overflow-hidden max-w-full w-full focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-n-brand"
      :class="[
        single ? 'max-h-[22rem]' : 'h-full',
        {
          'aspect-[4/3]': single && !dimensions.width,
          'aspect-square': !single && !(total === 3 && index === 0),
        },
      ]"
      :aria-label="label"
      @click="emit('open', attachment)"
    >
      <!-- Native SVG dimensions reserve arbitrary aspect ratios without inline CSS. -->
      <svg
        v-if="single && dimensions.width && dimensions.height"
        :viewBox="`0 0 ${dimensions.width} ${dimensions.height}`"
        :width="dimensions.width"
        :height="dimensions.height"
        aria-hidden="true"
        class="invisible max-h-[22rem] max-w-full"
        :class="tiny ? 'mx-auto' : 'w-full h-auto'"
      />
      <span
        v-if="!isLoaded && !hasError"
        class="absolute inset-0 animate-pulse motion-reduce:animate-none bg-n-alpha-2"
        aria-hidden="true"
      />
      <video
        v-if="isVideo && !hasError && !attachment.thumbUrl"
        :src="attachment.dataUrl"
        class="absolute inset-0 size-full object-cover"
        muted
        playsinline
        preload="metadata"
        @loadeddata="onLoad"
        @error="onError"
      />
      <img
        v-else-if="!hasError"
        :src="src"
        :alt="alt"
        :width="dimensions.width"
        :height="dimensions.height"
        loading="lazy"
        decoding="async"
        class="absolute inset-0 size-full skip-context-menu"
        :class="single && !tall ? 'object-contain' : 'object-cover object-top'"
        @load="handleLoad"
        @error="onError"
      />
      <span
        v-if="isVideo && !hasError"
        class="absolute inset-0 grid place-items-center"
      >
        <Icon
          icon="i-teenyicons-play-small-solid"
          class="size-7 rounded-full bg-n-slate-1/60 text-n-slate-12/80"
        />
      </span>
      <span
        v-if="tall && !hasError"
        class="absolute inset-x-0 bottom-0 h-16 flex items-end justify-center pb-2 bg-gradient-to-t from-n-slate-12/50"
      >
        <span
          class="rounded-full bg-n-slate-12/50 px-2.5 py-1 text-xs font-medium text-white"
          >{{ t('COMPONENTS.MEDIA.VIEW_FULL') }}</span
        >
      </span>
      <span
        v-if="more && !hasError"
        class="absolute inset-0 grid place-items-center bg-n-slate-12/45 text-white text-xl font-semibold"
      >
        {{ t('COMPONENTS.MEDIA.MORE', { count: more }) }}
      </span>
    </button>
    <div
      v-if="hasError"
      class="relative flex flex-col items-start gap-2 p-3 text-xs text-n-slate-11"
      role="status"
    >
      <Icon icon="i-lucide-image-off" />
      <span>{{ errorText }}</span>
      <div v-if="!isExpired" class="flex flex-wrap gap-1">
        <Button
          size="xs"
          intent="secondary"
          :label="t('COMPONENTS.MEDIA.RETRY')"
          @click="retry"
        />
        <a
          :href="attachment.dataUrl"
          target="_blank"
          rel="noopener noreferrer"
          class="underline"
          >{{ t('COMPONENTS.MEDIA.OPEN_LINK') }}</a
        >
      </div>
    </div>
    <div
      v-else
      class="absolute bottom-2 end-2 flex gap-1 [@media(hover:hover)]:opacity-0 group-hover:opacity-100 group-focus-within:opacity-100 focus-within:opacity-100 [@media(hover:none)]:opacity-100"
    >
      <Button
        size="xs"
        intent="secondary"
        icon="i-lucide-expand"
        :aria-label="t('COMPONENTS.MEDIA.EXPAND')"
        @click="emit('open', attachment)"
      />
      <Button
        size="xs"
        intent="tertiary"
        icon="i-lucide-download"
        :aria-label="t('CONVERSATION.DOWNLOAD')"
        :is-loading="isDownloading"
        :disabled="isDownloading"
        @click="download"
      />
    </div>
  </figure>
</template>
