import { computed, reactive, unref } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';

const preferences = reactive({});
export const cancelledVisibilityKey = accountId =>
  `${LOCAL_STORAGE_KEYS.CALENDAR_SHOW_CANCELLED}:${accountId}`;

export function useCalendarCancelledVisibility() {
  const { accountId } = useAccount();
  const key = computed(() => cancelledVisibilityKey(unref(accountId)));
  const showCancelled = computed({
    get() {
      if (!(key.value in preferences)) {
        preferences[key.value] = LocalStorage.get(key.value) === true;
      }
      return preferences[key.value];
    },
    set(value) {
      preferences[key.value] = value;
      LocalStorage.set(key.value, value);
    },
  });
  return { showCancelled };
}
