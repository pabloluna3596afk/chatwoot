import { computed, toValue, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useLoadWithRetry } from 'dashboard/composables/loadWithRetry';

const CHANNEL_NAMES = {
  'Channel::Instagram': 'Instagram',
  'Channel::FacebookPage': 'Facebook',
  'Channel::Whatsapp': 'WhatsApp',
};

export function useMediaState(attachment, channelType = '', source = null) {
  const { t } = useI18n();
  const { isLoaded, hasError, loadWithRetry } = useLoadWithRetry();
  const isExternal = computed(() => {
    const item = toValue(attachment);
    // External URLs are serialized as dataUrl, without an external_url flag.
    return Boolean(
      item.externalUrl ||
        (CHANNEL_NAMES[toValue(channelType)] &&
          item.dataUrl &&
          !item.dataUrl.includes('/rails/active_storage/'))
    );
  });
  const isExpired = computed(() => hasError.value && isExternal.value);
  const errorText = computed(() => {
    if (!isExpired.value) return t('COMPONENTS.MEDIA.LOAD_FAILED');
    const channel = CHANNEL_NAMES[toValue(channelType)];
    return channel
      ? t('COMPONENTS.MEDIA.EXPIRED', { channel })
      : t('COMPONENTS.MEDIA.EXPIRED_GENERIC');
  });
  const onLoad = () => {
    isLoaded.value = true;
    hasError.value = false;
  };
  const onError = () => {
    hasError.value = true;
    isLoaded.value = false;
  };
  const retry = async () => {
    hasError.value = false;
    isLoaded.value = false;
    const item = toValue(attachment);
    // Retrying a video remounts its native element; Image cannot load video bytes.
    if (['video', 'ig_reel'].includes(item.fileType) && !item.thumbUrl) return;
    await loadWithRetry(toValue(source) || toValue(attachment).dataUrl);
  };
  watch(
    () => toValue(source) || toValue(attachment).dataUrl,
    () => {
      isLoaded.value = false;
      hasError.value = false;
    }
  );
  return { isLoaded, hasError, isExpired, errorText, onLoad, onError, retry };
}
