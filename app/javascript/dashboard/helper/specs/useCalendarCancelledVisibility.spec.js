import { effectScope, ref } from 'vue';
import { LocalStorage } from 'shared/helpers/localStorage';
import {
  useCalendarCancelledVisibility,
  cancelledVisibilityKey,
} from '../useCalendarCancelledVisibility';

const { context } = vi.hoisted(() => ({ context: {} }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: context.accountId }),
}));
vi.mock('shared/helpers/localStorage', () => ({
  LocalStorage: { get: vi.fn(), set: vi.fn() },
}));

it('persists and shares the preference by account and reacts to account changes', () => {
  context.accountId = ref(101);
  LocalStorage.get.mockImplementation(
    key => key === cancelledVisibilityKey(202)
  );
  const scope = effectScope();
  scope.run(() => {
    const first = useCalendarCancelledVisibility();
    const second = useCalendarCancelledVisibility();
    expect(first.showCancelled.value).toBe(false);
    first.showCancelled.value = true;
    expect(LocalStorage.set).toHaveBeenCalledWith(
      cancelledVisibilityKey(101),
      true
    );
    expect(second.showCancelled.value).toBe(true);
    context.accountId.value = 202;
    expect(first.showCancelled.value).toBe(true);
    first.showCancelled.value = false;
    expect(LocalStorage.set).toHaveBeenLastCalledWith(
      cancelledVisibilityKey(202),
      false
    );
    context.accountId.value = 101;
    expect(first.showCancelled.value).toBe(true);
  });
  scope.stop();
});
