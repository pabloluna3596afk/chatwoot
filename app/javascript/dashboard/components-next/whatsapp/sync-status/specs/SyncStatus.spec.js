import { mount } from '@vue/test-utils';
import SyncStatus from '../SyncStatus.vue';

const mountIt = props =>
  mount(SyncStatus, {
    props: { label: 'Updated: {date}', buttonLabel: 'Sync', ...props },
  });

describe('SyncStatus', () => {
  it('shows the date and the hour next to one refresh button', () => {
    const wrapper = mountIt({ date: new Date(2026, 9, 9, 14, 32) });
    const text = wrapper.get('[data-testid="sync-status-text"]').text();
    expect(text).toContain('Updated:');
    expect(text).toMatch(/14:32|2:32/);
    expect(wrapper.get('[data-testid="sync-status-button"]').exists()).toBe(
      true
    );
  });

  it('shows only the time when short and the date is today', () => {
    const now = new Date();
    now.setHours(9, 5, 0, 0);
    const wrapper = mountIt({ date: now, short: true });
    expect(wrapper.get('[data-testid="sync-status-text"]').text()).not.toMatch(
      /20\d\d/
    );
  });

  it('shows no line without a date and emits refresh on click', async () => {
    const wrapper = mountIt({ date: null });
    expect(wrapper.find('[data-testid="sync-status-text"]').exists()).toBe(
      false
    );
    await wrapper.get('[data-testid="sync-status-button"]').trigger('click');
    expect(wrapper.emitted('refresh')).toHaveLength(1);
  });

  it('disables the button while loading', () => {
    const wrapper = mountIt({ isLoading: true });
    expect(
      wrapper.get('[data-testid="sync-status-button"]').attributes('disabled')
    ).toBeDefined();
  });
});
