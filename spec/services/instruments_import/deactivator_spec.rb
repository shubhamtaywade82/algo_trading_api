# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstrumentsImport::Deactivator, type: :service do
  let(:started_at) { Time.current }

  it 'retires rows the feed stopped listing' do
    stale = create(:derivative, last_seen_at: started_at - 2.days)

    described_class.call(started_at: started_at)

    expect(stale.reload).not_to be_active
  end

  it 'leaves rows the current run stamped alone' do
    fresh = create(:derivative, last_seen_at: started_at + 1.second)

    described_class.call(started_at: started_at)

    expect(fresh.reload).to be_active
  end

  it 'retires rows that predate the last_seen_at column' do
    legacy = create(:instrument, last_seen_at: nil)

    described_class.call(started_at: started_at)

    expect(legacy.reload).not_to be_active
  end

  it 'reports how many rows it retired across both tables' do
    create(:instrument, last_seen_at: started_at - 2.days)
    create(:derivative, last_seen_at: started_at - 2.days)

    expect(described_class.call(started_at: started_at)).to eq(deactivated_rows: 2)
  end

  it 'never deletes, because orders and positions still reference these rows' do
    create(:derivative, last_seen_at: started_at - 2.days)

    expect { described_class.call(started_at: started_at) }.not_to change(Derivative, :count)
  end

  it 'is idempotent — a second sweep does not re-count what it already retired' do
    create(:derivative, last_seen_at: started_at - 2.days)
    described_class.call(started_at: started_at)

    expect(described_class.call(started_at: started_at)).to eq(deactivated_rows: 0)
  end
end
