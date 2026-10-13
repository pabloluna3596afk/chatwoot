require 'rails_helper'

# These scenarios build a whole account (agents, inboxes, contacts, events) and check many numbers of one run, so they
# keep many memoized helpers and expectations per example.
# rubocop:disable RSpec/MultipleExpectations, RSpec/MultipleMemoizedHelpers, Performance/CollectionLiteralInLoop

RSpec.describe Reports::PanelRunnerService do
  let(:account) { create(:account, reporting_timezone: 'UTC') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:since_time) { Time.utc(2026, 10, 5) }
  let(:until_time) { Time.utc(2026, 10, 11, 23, 59, 59) }
  let(:panel) { build(:saved_report_panel, account: account, created_by: admin, widgets: widgets, filters: filters) }
  let(:filters) { [] }
  let(:runner) do
    described_class.new(panel: panel, account: account, user: admin, date_overrides: { since: since_time.to_i, until: until_time.to_i })
  end
  let(:result) { runner.perform[:widgets].first.with_indifferent_access }

  describe 'date boundaries' do
    let(:widgets) { [{ id: 'count', type: 'metric', metric: 'conversations_count' }] }

    it 'counts the first and final second of a seven-day preset, excluding the previous day' do
      account.update!(reporting_timezone: 'America/Guayaquil')
      times = [Time.utc(2026, 10, 5, 4, 59, 59), Time.utc(2026, 10, 5, 5),
               Time.utc(2026, 10, 12, 4, 59, 59), Time.utc(2026, 10, 12, 4, 59, 59) + 0.5]
      times.each do |created_at|
        create(:conversation, account: account, inbox: inbox, created_at: created_at)
      end
      travel_to Time.utc(2026, 10, 12, 2) do
        report = described_class.new(panel: panel, account: account, user: admin).perform
        expect(report[:since]).to eq(Time.utc(2026, 10, 5, 5).to_i)
        expect(report[:until]).to eq(Time.utc(2026, 10, 12, 4, 59, 59).to_i)
        expect(report[:widgets].first[:value]).to eq(3)
        panel.filters = [{ attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [inbox.id] }]
        filtered_report = described_class.new(panel: panel, account: account, user: admin).perform
        expect(filtered_report[:widgets].first[:value]).to eq(3)
      end
    end

    it 'rejects a partial override before executing widgets' do
      service = described_class.new(panel: panel, account: account, user: admin, date_overrides: { since: since_time.to_i })
      expect { service.perform }.to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::InvalidReportDateRange') })
    end

    it 'rejects explicit null overrides rather than using the saved preset' do
      service = described_class.new(panel: panel, account: account, user: admin, date_overrides: { since: nil, until: nil })
      expect { service.perform }.to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::InvalidReportDateRange') })
    end
  end

  describe 'contact pivot measures (D5)' do
    let(:measures) { %w[contact_ca:amount__sum contact_ca:amount__avg contact_ca:status__count__eq__active contact_ca:score__sum] }
    let(:widgets) do
      [{ id: 'pivot', type: 'table', table_kind: 'inbox_summary', columns: ['name'] + measures,
         pivot: { column_attribute: 'ca:segment', column_values: %w[A B] } }]
    end

    it 'deduplicates each measure independently within each bucket' do
      create(:custom_attribute_definition, account: account, attribute_key: 'segment', attribute_model: :conversation_attribute)
      contact = create(:contact, account: account, custom_attributes: { amount: 100, status: 'active', score: 7 })
      %w[A A B].each do |segment|
        create(:conversation, account: account, inbox: inbox, contact: contact, created_at: since_time,
                              custom_attributes: { segment: segment })
      end

      expect(result[:error]).to be_nil
      row = result[:rows].find { |item| item[:id] == inbox.id }
      %w[A B].each do |segment|
        expect(row["contact_ca:amount__sum__pv__#{segment}"]).to eq(100)
        expect(row["contact_ca:amount__avg__pv__#{segment}"]).to eq(100)
        expect(row["contact_ca:status__count__eq__active__pv__#{segment}"]).to eq(1)
        expect(row["contact_ca:score__sum__pv__#{segment}"]).to eq(7)
      end
    end
  end

  describe 'pivot totals (D6)' do
    let(:other_inbox) { create(:inbox, account: account) }
    let!(:empty_inbox) { create(:inbox, account: account) }
    let(:widgets) do
      [{ id: 'pivot', type: 'table', table_kind: 'inbox_summary', columns: %w[name ca:amount__avg ca:amount__min ca:amount__max],
         pivot: { column_attribute: 'ca:segment', column_values: %w[A B Empty] } }]
    end

    before do
      create(:custom_attribute_definition, account: account, attribute_key: 'segment', attribute_model: :conversation_attribute)
      [[inbox, 'A', 10], [inbox, 'A', 10], [inbox, 'A', 10], [inbox, 'B', 100], [other_inbox, 'A', 50]].each do |box, segment, amount|
        create(:conversation, account: account, inbox: box, created_at: since_time, custom_attributes: { segment: segment, amount: amount })
      end
    end

    it 'combines raw values for row, column and grand averages and ignores empty cells' do
      expect(result[:error]).to be_nil
      row = result[:rows].find { |item| item[:id] == inbox.id }
      expect(row['ca:amount__avg__pv__A']).to eq(10)
      expect(row['ca:amount__avg__pv__B']).to eq(100)
      expect(row['ca:amount__avg']).to eq(32.5)
      expect(row['ca:amount__min']).to eq(10)
      expect(row['ca:amount__max']).to eq(100)
      expect(result[:totals][:columns]['ca:amount__avg__pv__A']).to eq(20)
      expect(result[:totals][:columns]['ca:amount__avg__pv__B']).to eq(100)
      expect(result[:totals][:columns]['ca:amount__avg']).to eq(36)
      expect(result[:totals][:columns]['ca:amount__min']).to eq(10)
      expect(result[:totals][:columns]['ca:amount__max']).to eq(100)
      %w[avg min max].each do |op|
        expect(row["ca:amount__#{op}__pv__Empty"]).to be_nil
        expect(result[:totals][:columns]["ca:amount__#{op}__pv__Empty"]).to be_nil
        empty_row = result[:rows].find { |item| item[:id] == empty_inbox.id }
        expect(empty_row["ca:amount__#{op}"]).to be_nil
      end
    end
  end

  describe 'distinct resolution conversations (D7)' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:team) { create(:team, account: account) }
    let(:label) { create(:label, account: account, title: 'sales') }
    let(:old_conversation) do
      create(:conversation, account: account, inbox: inbox, team: team, assignee: agent, created_at: since_time - 30.days,
                            custom_attributes: { segment: 'A' })
    end
    let(:current_conversation) do
      create(:conversation, account: account, inbox: inbox, team: team, assignee: agent, created_at: since_time,
                            custom_attributes: { segment: 'A' })
    end

    before do
      create(:team_member, team: team, user: agent)
      create(:custom_attribute_definition, account: account, attribute_key: 'segment', attribute_model: :conversation_attribute)
      [old_conversation, current_conversation].each do |conversation|
        conversation.add_labels([label.title])
        2.times do
          create(:reporting_event, account: account, inbox: inbox, conversation: conversation, user: agent,
                                   name: 'conversation_resolved', created_at: since_time + 1.hour)
        end
      end
      no_event = create(:conversation, account: account, inbox: inbox, team: team, assignee: agent,
                                       status: :resolved, created_at: since_time, custom_attributes: { segment: 'A' })
      no_event.add_labels([label.title])
      create(:reporting_event, account: account, inbox: inbox, conversation: no_event, user: agent,
                               name: 'conversation_resolved', created_at: since_time - 1.second)
      create(:reporting_event, account: account, inbox: inbox, conversation: no_event, user: agent,
                               name: 'conversation_resolved', created_at: until_time + 1.second)
    end

    context 'when two agents resolve the same conversation' do
      let(:widgets) do
        [{ id: 'agents', type: 'table', table_kind: 'agent_summary', columns: %w[name resolved_conversations_count],
           pivot: { column_attribute: 'ca:segment', column_values: ['A'] } }]
      end

      it 'counts the conversation once in the pivot footer while crediting both actors in their rows' do
        other_actor = create(:user, account: account, role: :agent)
        create(:reporting_event, account: account, inbox: inbox, conversation: old_conversation, user: other_actor,
                                 name: 'conversation_resolved', created_at: since_time + 2.hours)

        expect(result[:error]).to be_nil
        expect(result[:rows].sum { |row| row['resolved_conversations_count'] }).to eq(3)
        expect(result[:totals][:columns]['resolved_conversations_count']).to eq(2)
        expect(result[:totals][:columns]['resolved_conversations_count__pv__A']).to eq(2)
      end
    end

    [false, true].each do |filtered|
      context "with #{filtered ? 'an inbox filter' : 'no filters'}" do
        let(:filters) do
          filtered ? [{ attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [inbox.id], query_operator: nil }] : []
        end

        context 'with a resolution KPI and chart' do
          let(:widgets) do
            [{ id: 'kpi', type: 'metric', metric: 'resolutions_count' },
             { id: 'chart', type: 'chart', metric: 'resolutions_count', group_by: 'day' }]
          end
          let(:normal_report_params) do
            {
              type: :account, metric: 'resolutions_count', group_by: 'day', timezone_offset: 0,
              since: since_time.to_i.to_s, until: (until_time.to_i + 1).to_s,
              business_hours: false
            }
          end

          it 'counts two conversations rather than four events, including the old reopened conversation' do
            expect(V2::ReportBuilder).not_to receive(:new)
            report = runner.perform
            expect(report[:widgets].map { |widget| widget[:error] }).to eq([nil, nil])
            expect(report[:widgets][0][:value]).to eq(2)
            expect(report[:widgets][1][:points].sum { |point| point[:value] }).to eq(2)
          end

          it 'keeps normal reports counting four resolution events while panels count two conversations' do
            normal_report = V2::ReportBuilder.new(account, normal_report_params)

            expect(normal_report.summary[:resolutions_count]).to eq(4)
            expect(normal_report.build.sum { |point| point[:value] }).to eq(4)
            expect(result[:value]).to eq(2)
          end
        end

        %w[agent_summary inbox_summary team_summary label_summary].each do |kind|
          [false, true].each do |pivot|
            context "with #{kind} #{pivot ? 'pivot' : 'summary'}" do
              let(:widgets) do
                widget = { id: 'table', type: 'table', table_kind: kind, columns: %w[name conversations_count resolved_conversations_count] }
                widget[:pivot] = { column_attribute: 'ca:segment', column_values: ['A'] } if pivot
                [widget]
              end

              it 'reports two distinct event-period conversations regardless of their current status' do
                expect(result[:error]).to be_nil
                expect(result[:rows].sum { |row| row['resolved_conversations_count'] }).to eq(2)
                expect(result[:rows].sum { |row| row['resolved_conversations_count__pv__A'] }).to eq(2) if pivot
              end
            end
          end
        end
      end
    end

    %w[account agent inbox team label].each do |scope_type|
      context "with unfiltered #{scope_type} resolution widgets" do
        let(:scope_ids) { { 'agent' => agent.id, 'inbox' => inbox.id, 'team' => team.id, 'label' => label.id } }
        let(:widgets) do
          [{ id: 'kpi', type: 'metric', metric: 'resolutions_count', scope_type: scope_type, scope_id: scope_ids[scope_type] },
           { id: 'chart', type: 'chart', metric: 'resolutions_count', scope_type: scope_type, scope_id: scope_ids[scope_type] }]
        end

        it 'preserves the selected scope while counting distinct conversations in the period' do
          other_actor = create(:user, account: account, role: :agent)
          other_inbox = create(:inbox, account: account)
          other_conversation = create(:conversation, account: account, inbox: other_inbox, assignee: other_actor, created_at: since_time - 30.days)
          create(:reporting_event, account: account, inbox: other_inbox, conversation: other_conversation, user: other_actor,
                                   name: 'conversation_resolved', created_at: since_time + 1.hour)

          report = runner.perform
          expected_count = scope_type == 'account' ? 3 : 2
          expect(report[:widgets].map { |widget| widget[:error] }).to eq([nil, nil])
          expect(report[:widgets][0][:value]).to eq(expected_count)
          expect(report[:widgets][1][:points].sum { |point| point[:value] }).to eq(expected_count)
        end
      end
    end
  end

  describe 'event agent attribution (D8)' do
    let(:actor) { create(:user, account: account, role: :agent) }
    let(:assignee) { create(:user, account: account, role: :agent) }
    let(:widgets) do
      [{ id: 'agents', type: 'table', table_kind: 'agent_summary',
         columns: %w[name conversations_count resolved_conversations_count avg_first_response_time avg_reply_time] }]
    end

    before do
      create(:custom_attribute_definition, account: account, attribute_key: 'segment', attribute_model: :conversation_attribute)
      conversation = create(:conversation, account: account, inbox: inbox, assignee: assignee, created_at: since_time,
                                           custom_attributes: { segment: 'A' })
      { 'conversation_resolved' => 100, 'first_response' => 20, 'reply_time' => 40 }.each do |name, value|
        create(:reporting_event, account: account, inbox: inbox, conversation: conversation, user: actor,
                                 name: name, value: value, created_at: since_time + 1.hour)
      end
      { 'first_response' => 60, 'reply_time' => 80 }.each do |name, value|
        create(:reporting_event, account: account, inbox: inbox, conversation: conversation, user: nil,
                                 name: name, value: value, created_at: since_time + 1.hour)
      end
      old_assigned = create(:conversation, account: account, inbox: inbox, assignee: assignee, created_at: since_time - 30.days,
                                           custom_attributes: { segment: 'A' })
      2.times do
        create(:reporting_event, account: account, inbox: inbox, conversation: old_assigned, user: nil,
                                 name: 'conversation_resolved', created_at: since_time + 1.hour)
      end
    end

    [false, true].each do |filtered|
      context "with #{filtered ? 'an inbox filter' : 'no filters'}" do
        let(:filters) do
          filtered ? [{ attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [inbox.id], query_operator: nil }] : []
        end

        it 'credits the event actor and counts nil-actor resolutions in the unassigned row' do
          expect(result[:error]).to be_nil
          actor_row = result[:rows].find { |row| row[:id] == actor.id }
          assignee_row = result[:rows].find { |row| row[:id] == assignee.id }
          unassigned_row = result[:rows].find { |row| row[:id] == 0 }
          expect(actor_row[:resolved_conversations_count]).to eq(1)
          expect(actor_row[:avg_resolution_time]).to eq(100)
          expect(actor_row[:avg_first_response_time]).to eq(20)
          expect(actor_row[:avg_reply_time]).to eq(40)
          expect(assignee_row[:conversations_count]).to eq(1)
          expect(assignee_row[:resolved_conversations_count]).to eq(0)
          expect(assignee_row[:avg_first_response_time]).to be_nil
          expect(assignee_row[:avg_reply_time]).to be_nil
          expect(unassigned_row[:resolved_conversations_count]).to eq(1)
          expect(unassigned_row[:avg_first_response_time]).to eq(60)
          expect(unassigned_row[:avg_reply_time]).to eq(80)
        end

        context 'with a pivot' do
          let(:widgets) do
            [{ id: 'agents', type: 'table', table_kind: 'agent_summary', columns: %w[name resolved_conversations_count],
               pivot: { column_attribute: 'ca:segment', column_values: ['A'] } }]
          end

          it 'uses event actors for pivot resolutions, including nil actors on assigned conversations' do
            expect(result[:error]).to be_nil
            actor_row = result[:rows].find { |row| row[:id] == actor.id }
            assignee_row = result[:rows].find { |row| row[:id] == assignee.id }
            unassigned_row = result[:rows].find { |row| row[:id] == 0 }
            expect(actor_row['resolved_conversations_count__pv__A']).to eq(1)
            expect(assignee_row['resolved_conversations_count__pv__A']).to eq(0)
            expect(unassigned_row['resolved_conversations_count__pv__A']).to eq(1)
          end
        end
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/MultipleMemoizedHelpers, Performance/CollectionLiteralInLoop
