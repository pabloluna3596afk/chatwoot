import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useFunctionGetter } from 'dashboard/composables/store';

export function useAssistantSettings() {
  const { t } = useI18n();
  const route = useRoute();
  const store = useStore();

  const assistantId = computed(() => Number(route.params.assistantId));
  const assistant = useFunctionGetter(
    'captainAssistants/getRecord',
    assistantId
  );

  const updateAssistant = async updatedAssistant => {
    try {
      await store.dispatch('captainAssistants/update', {
        id: assistantId.value,
        ...updatedAssistant,
      });
      useAlert(t('CAPTAIN.ASSISTANTS.EDIT.SUCCESS_MESSAGE'));
    } catch (error) {
      useAlert(error?.message || t('CAPTAIN.ASSISTANTS.EDIT.ERROR_MESSAGE'));
    }
  };

  const uploadAvatar = async ({ file }) => {
    try {
      await store.dispatch('captainAssistants/updateAvatar', {
        id: assistantId.value,
        file,
      });
      useAlert(t('CAPTAIN.ASSISTANTS.FORM.AVATAR.SUCCESS_UPLOAD'));
    } catch (error) {
      useAlert(
        error?.message || t('CAPTAIN.ASSISTANTS.FORM.AVATAR.ERROR_UPLOAD')
      );
    }
  };

  const deleteAvatar = async () => {
    try {
      await store.dispatch('captainAssistants/deleteAvatar', assistantId.value);
      useAlert(t('CAPTAIN.ASSISTANTS.FORM.AVATAR.SUCCESS_DELETE'));
    } catch (error) {
      useAlert(
        error?.message || t('CAPTAIN.ASSISTANTS.FORM.AVATAR.ERROR_DELETE')
      );
    }
  };

  return {
    assistantId,
    assistant,
    updateAssistant,
    uploadAvatar,
    deleteAvatar,
  };
}
