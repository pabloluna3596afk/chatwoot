import { computed } from 'vue';
import { useAccount } from './useAccount';
import { useMapGetter } from './store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

export function useConversationTranslation() {
  const { currentAccount } = useAccount();
  const currentChat = useMapGetter('getSelectedChat');
  const isFeatureEnabled = useMapGetter('accounts/isFeatureEnabledonAccount');
  const accountEnabled = computed(
    () =>
      isFeatureEnabled.value(
        currentAccount.value?.id,
        FEATURE_FLAGS.AUTO_TRANSLATE
      ) && currentAccount.value?.settings?.auto_translate === true
  );
  const controlEnabled = computed(() =>
    isFeatureEnabled.value(
      currentAccount.value?.id,
      FEATURE_FLAGS.CONVERSATION_AUTO_TRANSLATE
    )
  );
  const disabled = computed(
    () =>
      controlEnabled.value &&
      currentChat.value?.additional_attributes?.auto_translate_disabled === true
  );
  const enabled = computed(() => accountEnabled.value && !disabled.value);
  const canToggle = computed(
    () => accountEnabled.value && controlEnabled.value
  );

  return { enabled, canToggle, disabled };
}
