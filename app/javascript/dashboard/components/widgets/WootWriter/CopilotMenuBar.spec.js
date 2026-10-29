import { mount } from '@vue/test-utils';
import { REPLY_EDITOR_MODES } from './constants';
import CopilotMenuBar from './CopilotMenuBar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useMapGetter } from 'dashboard/composables/store';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: vi.fn(),
}));

describe('CopilotMenuBar', () => {
  beforeEach(() => {
    useMapGetter.mockReturnValue({ value: REPLY_EDITOR_MODES.REPLY });
  });

  it('keeps visibility and disabled state stable across the plan and editor matrix', () => {
    const testCases = [false, true].flatMap(captainTasksEnabled =>
      [false, true].flatMap(latestMessageIncoming =>
        [REPLY_EDITOR_MODES.REPLY, REPLY_EDITOR_MODES.NOTE].flatMap(mode =>
          [false, true].map(hasContent => ({
            captainTasksEnabled,
            latestMessageIncoming,
            mode,
            hasContent,
          }))
        )
      )
    );

    testCases.forEach(
      ({ captainTasksEnabled, latestMessageIncoming, mode, hasContent }) => {
        useMapGetter.mockReturnValue({ value: mode });
        let disabledReason = '';
        if (!captainTasksEnabled) disabledReason = 'plan';
        if (!disabledReason && !latestMessageIncoming) {
          disabledReason = 'incoming';
        }
        const wrapper = mount(CopilotMenuBar, {
          props: {
            conversationId: 12,
            captainTasksEnabled,
            hasContent,
            replySuggestionDisabledReason: disabledReason,
          },
          global: {
            mocks: { $t: key => key },
            stubs: {
              DropdownBody: { template: '<div><slot /></div>' },
            },
          },
        });
        const suggestion = wrapper
          .findAllComponents(Button)
          .find(button =>
            button.props('label')?.includes('REPLY_OPTIONS.SUGGESTION')
          );

        if (mode === REPLY_EDITOR_MODES.NOTE) {
          expect(suggestion).toBeUndefined();
        } else {
          expect(suggestion).toBeDefined();
          expect(suggestion.element.disabled).toBe(!!disabledReason);
          if (disabledReason) {
            expect(wrapper.text()).toContain(
              `SUGGESTION_${disabledReason.toUpperCase()}_REQUIRED`
            );
          }
        }
        wrapper.unmount();
      }
    );
  });
});
