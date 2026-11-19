import { computed, toValue } from 'vue';
import { useI18n } from 'vue-i18n';

export const ASSISTANT_NAME_MARKER = '\u2063';
export const MAX_ASSISTANT_NAME_LENGTH = 24;

export const truncateAssistantName = name => {
  const characters = Array.from(name);
  return characters.length > MAX_ASSISTANT_NAME_LENGTH
    ? `${characters.slice(0, MAX_ASSISTANT_NAME_LENGTH).join('')}…`
    : name;
};

export function useAssistantName(assistant) {
  const { t } = useI18n();
  const fullName = computed(
    () =>
      toValue(assistant)?.name?.replaceAll(ASSISTANT_NAME_MARKER, '').trim() ||
      'Captain'
  );
  const assistantName = computed(() => truncateAssistantName(fullName.value));
  const nameText = (key, params) =>
    t(key, { ...params, assistantName: assistantName.value });
  const nameTextFrom = text =>
    text.replace(/\bCaptain\b/g, () => assistantName.value);
  const markedName = computed(
    () => `${ASSISTANT_NAME_MARKER}${fullName.value}${ASSISTANT_NAME_MARKER}`
  );
  const nameRich = (key, params) =>
    t(key, { ...params, assistantName: markedName.value });
  const nameRichFrom = text =>
    text.replace(/\bCaptain\b/g, () => markedName.value);

  return { assistantName, nameText, nameTextFrom, nameRich, nameRichFrom };
}
