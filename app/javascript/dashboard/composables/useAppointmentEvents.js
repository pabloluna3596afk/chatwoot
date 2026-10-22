import { ref, watch, onScopeDispose, toValue } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAbortableRequest } from './useAbortableRequest';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

// Invalidation carries identities only. Each surface reloads through its authorized API.
export function useAppointmentEvents({
  context,
  contactId,
  fetchEvents,
  enabled = true,
}) {
  const { accountId } = useAccount();
  const events = ref([]);
  const hasError = ref(false);
  const request = useAbortableRequest();
  const load = async () => {
    hasError.value = false;
    if (!toValue(enabled)) {
      request.abort();
      return;
    }
    try {
      const response = await request.run(fetchEvents);
      if (response) events.value = response.data.payload || [];
    } catch (error) {
      hasError.value = true;
    }
  };
  watch(
    [accountId, context, () => toValue(enabled)],
    () => {
      events.value = [];
      load();
    },
    { immediate: true }
  );
  const onChanged = data => {
    if (
      Number(data.account_id) === accountId.value &&
      data.contact_ids.some(id => String(id) === String(contactId()))
    )
      load();
  };
  emitter.on(BUS_EVENTS.CALENDAR_EVENTS_CHANGED, onChanged);
  emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT_COMPLETED, load);
  onScopeDispose(() => {
    emitter.off(BUS_EVENTS.CALENDAR_EVENTS_CHANGED, onChanged);
    emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT_COMPLETED, load);
  });
  return { events, hasError, isLoading: request.isPending, load };
}
