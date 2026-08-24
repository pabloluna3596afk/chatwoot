import { computed } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useDarkMode } from 'dashboard/composables/useDarkMode';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import {
  CHAT_CANVAS_IDS,
  CHAT_CANVAS_THEMES,
  DEFAULT_CHAT_CANVAS,
  resolveChatCanvasId,
} from 'dashboard/helper/chatSkin';

const i18nKeyPrefix = 'PROFILE_SETTINGS.FORM.INTERFACE_SECTION.CHAT_CANVAS';

export function useChatCanvas() {
  const { uiSettings, updateUISettings } = useUISettings();
  const { t } = useI18n();
  const { isDark } = useDarkMode();

  const currentCanvasId = computed(() =>
    resolveChatCanvasId(uiSettings.value?.chat_canvas)
  );

  const canvasOptions = computed(() =>
    CHAT_CANVAS_IDS.map(id => {
      const theme = CHAT_CANVAS_THEMES[id];
      return {
        id,
        label: t(`${i18nKeyPrefix}.OPTIONS.${id.toUpperCase()}.LABEL`),
        description: t(
          `${i18nKeyPrefix}.OPTIONS.${id.toUpperCase()}.DESCRIPTION`
        ),
        preview: isDark.value ? theme.previewDark : theme.preview,
      };
    })
  );

  const updateChatCanvas = async canvasId => {
    const nextId = resolveChatCanvasId(canvasId);
    try {
      await updateUISettings({ chat_canvas: nextId });
      useAlert(t(`${i18nKeyPrefix}.UPDATE_SUCCESS`));
    } catch (error) {
      useAlert(t(`${i18nKeyPrefix}.UPDATE_ERROR`));
    }
  };

  return {
    currentCanvasId,
    canvasOptions,
    updateChatCanvas,
    defaultCanvasId: DEFAULT_CHAT_CANVAS,
  };
}

export default useChatCanvas;
