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
  transparent: { type: Boolean, default: false },
});
const emit = defineEmits(['open', 'error']);
const { t } = useI18n();
const single = computed(() => props.total === 1);
const isVideo = computed(() =>
  ['video', 'ig_reel'].includes(props.attachment.fileType)
);
const dimensions = computed(() => ({
  width: props.attachment.width,
  height: props.attachment.height,
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
  t(
    isVideo.value
      ? 'COMPONENTS.MEDIA.VIDEO_N_OF'
      : 'COMPONENTS.MEDIA.PHOTO_N_OF',
    {
      index: props.index + 1,
      total: props.total,
    }
  )
);
const { isLoaded, hasError, isExpired, errorText, onLoad, onError, retry } =
  useMediaState(
    () => props.attachment,
    () => props.channelType,
    src
  );
const videoDuration = shallowRef(0);
const durationLabel = computed(() => {
  const seconds = Math.floor(videoDuration.value);
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
});
const onMetadata = event => {
  const { duration } = event.target;
  videoDuration.value = Number.isFinite(duration) ? duration : 0;
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
    class="relative group overflow-hidden m-0 min-w-0"
    :class="[
      transparent ? 'bg-transparent' : 'bg-n-alpha-1',
      single
        ? tall
          ? 'rounded-lg w-[20rem] max-w-full h-[22rem]'
          : dimensions.width
            ? 'rounded-lg w-fit max-w-[20rem] max-h-[22rem]'
            : 'rounded-lg w-[20rem] max-w-full'
        : 'h-full',
      {
        'row-span-2': total === 3 && index === 0,
        'p-3 grid place-items-center': tiny,
      },
    ]"
  >
    <button
      v-if="!hasError"
      type="button"
      class="relative block overflow-hidden max-w-full focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-n-brand"
      :class="[
        single
          ? tall
            ? 'w-full h-full'
            : dimensions.width
              ? 'w-auto max-h-[22rem]'
              : 'w-full'
          : 'w-full h-full',
        {
          'aspect-[4/3] w-[20rem]': single && !dimensions.width,
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
        :class="tiny ? 'mx-auto' : tall ? 'w-full h-full' : 'w-auto h-auto'"
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
        @loadedmetadata="onMetadata"
        @loadeddata="onLoad"
        @error="
          onError();
          emit('error');
        "
      />
      <img
        v-else-if="!hasError"
        :src="src"
        :alt="alt"
        :width="dimensions.width"
        :height="dimensions.height"
        loading="lazy"
        decoding="async"
        class="absolute inset-0 size-full skip-context-menu transition-opacity duration-200 motion-reduce:transition-none"
        :class="[
          { 'opacity-0': !isLoaded },
          single && !tall ? 'object-contain' : 'object-cover object-top',
        ]"
        @load="onLoad"
        @error="
          onError();
          emit('error');
        "
      />
      <span
        v-if="isVideo && !hasError"
        class="absolute inset-0 grid place-items-center"
      >
        <Icon
          icon="i-teenyicons-play-small-solid"
          class="size-12 p-2.5 rounded-full bg-black/60 text-white ring-1 ring-white/30 backdrop-blur-sm transition-transform group-hover:scale-105 motion-reduce:transform-none"
        />
      </span>
      <span
        v-if="isVideo && videoDuration > 0"
        class="absolute bottom-2 start-2 rounded-full bg-black/60 px-2 py-0.5 text-xs tabular-nums text-white"
        >{{ durationLabel }}</span
      >
      <span
        v-if="tall && !hasError"
        class="absolute inset-x-0 bottom-0 h-16 flex items-end justify-center pb-2 bg-gradient-to-t from-black/50"
      >
        <span
          class="rounded-full bg-black/55 px-2.5 py-1 text-xs font-medium text-white"
          >{{ t('COMPONENTS.MEDIA.VIEW_FULL') }}</span
        >
      </span>
      <span
        v-if="more && !hasError"
        class="absolute inset-0 grid place-items-center bg-black/55 text-white text-xl font-semibold"
      >
        {{ t('COMPONENTS.MEDIA.MORE', { count: more }) }}
      </span>
    </button>
    <div
      v-if="hasError"
      class="relative flex flex-col items-center justify-center gap-3 min-h-32 p-4 text-center text-sm leading-5 text-n-slate-11"
      role="status"
    >
      <Icon
        icon="i-lucide-image-off"
        class="size-10 p-2.5 rounded-full bg-n-alpha-2 text-n-slate-11"
      />
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
      v-else-if="single"
      class="absolute top-2 end-2 flex gap-1 rounded-lg bg-n-solid-1 p-0.5 shadow-sm [@media(hover:hover)]:opacity-0 group-hover:opacity-100 group-focus-within:opacity-100 focus-within:opacity-100 [@media(hover:none)]:opacity-100"
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
