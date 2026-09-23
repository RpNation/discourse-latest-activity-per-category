# frozen_string_literal: true

RSpec.describe DiscourseCategoryLatestTopics::LatestTopicsQuery do
  fab!(:category)

  before { Category.clear_subcategory_ids }
  after { Category.clear_subcategory_ids }

  describe "#call with cached descendants" do
    it "reuses the hierarchy when selecting topics for warmed categories" do
      child = Fabricate(:category, parent_category: category)
      winner = Fabricate(:topic, category: child)
      guardian = Guardian.new
      described_class.new(guardian: guardian, category_ids: [category.id, child.id]).call.to_a

      result = nil
      queries =
        track_sql_queries do
          result =
            described_class.new(guardian: guardian, category_ids: [category.id, child.id]).call.to_a
        end

      expect(
        result.map { |topic| [topic.category_latest_topic_category_id, topic.id] },
      ).to contain_exactly([category.id, winner.id], [child.id, winner.id])
      expect(queries.grep(/WITH RECURSIVE/i)).to be_empty
    end

    it "includes newly created descendants after the hierarchy has been cached" do
      previous = Fabricate(:topic, category: category, bumped_at: 1.day.ago)
      expect(
        described_class.new(guardian: Guardian.new, category_ids: [category.id]).call.map(&:id),
      ).to eq([previous.id])

      child = Fabricate(:category, parent_category: category)
      winner = Fabricate(:topic, category: child)

      expect(
        described_class.new(guardian: Guardian.new, category_ids: [category.id]).call.map(&:id),
      ).to eq([winner.id])
    end

    it "moves a descendant's latest topic to its new ancestor after reparenting" do
      other_category = Fabricate(:category)
      child = Fabricate(:category, parent_category: category)
      previous = Fabricate(:topic, category: category, bumped_at: 2.days.ago)
      other_previous = Fabricate(:topic, category: other_category, bumped_at: 2.days.ago)
      winner = Fabricate(:topic, category: child)
      query =
        described_class.new(guardian: Guardian.new, category_ids: [category.id, other_category.id])
      expect(
        query.call.map { |topic| [topic.category_latest_topic_category_id, topic.id] },
      ).to contain_exactly([category.id, winner.id], [other_category.id, other_previous.id])

      child.update!(parent_category: other_category)

      expect(
        query.call.map { |topic| [topic.category_latest_topic_category_id, topic.id] },
      ).to contain_exactly([category.id, previous.id], [other_category.id, winner.id])
    end

    it "refreshes the cached hierarchy after a descendant is destroyed" do
      child = Fabricate(:category, parent_category: category)
      winner = Fabricate(:topic, category: category)
      query = described_class.new(guardian: Guardian.new, category_ids: [category.id])
      expect(query.call.map(&:id)).to eq([winner.id])

      child.destroy!

      result = nil
      queries = track_sql_queries { result = query.call.to_a }

      expect(result.map(&:id)).to eq([winner.id])
      expect(queries.grep(/WITH RECURSIVE/i).size).to eq(1)
      expect(Category.subcategory_ids(category.id)).to eq([category.id])
    end

    it "honors a reduced nesting limit after the hierarchy has been cached" do
      SiteSetting.max_category_nesting = 3
      child = Fabricate(:category, parent_category: category)
      grandchild = Fabricate(:category, parent_category: child)
      child_topic = Fabricate(:topic, category: child, bumped_at: 1.day.ago)
      grandchild_topic = Fabricate(:topic, category: grandchild)
      query = described_class.new(guardian: Guardian.new, category_ids: [category.id])
      expect(query.call.map(&:id)).to eq([grandchild_topic.id])

      SiteSetting.max_category_nesting = 2

      expect(query.call.map(&:id)).to eq([child_topic.id])
    end

    it "checks each viewer's permissions while reusing the same hierarchy" do
      group = Fabricate(:group)
      private_child = Fabricate(:private_category, group: group, parent_category: category)
      public_topic = Fabricate(:topic, category: category, bumped_at: 1.day.ago)
      private_topic = Fabricate(:topic, category: private_child)
      allowed_user = Fabricate(:user, groups: [group])
      allowed_query =
        described_class.new(guardian: allowed_user.guardian, category_ids: [category.id])
      expect(allowed_query.call.map(&:id)).to eq([private_topic.id])

      public_result = nil
      queries =
        track_sql_queries do
          public_result =
            described_class.new(guardian: Guardian.new, category_ids: [category.id]).call.to_a
        end

      expect(public_result.map(&:id)).to eq([public_topic.id])
      expect(queries.grep(/WITH RECURSIVE/i)).to be_empty
      expect(allowed_query.call.map(&:id)).to eq([private_topic.id])
    end

    it "selects newly bumped topics without invalidating the hierarchy" do
      child = Fabricate(:category, parent_category: category)
      previous = Fabricate(:topic, category: child)
      winner = Fabricate(:topic, category: category, bumped_at: 1.day.ago)
      query = described_class.new(guardian: Guardian.new, category_ids: [category.id])
      expect(query.call.map(&:id)).to eq([previous.id])

      winner.update!(bumped_at: 1.minute.from_now)

      result = nil
      queries = track_sql_queries { result = query.call.to_a }

      expect(result.map(&:id)).to eq([winner.id])
      expect(queries.grep(/WITH RECURSIVE/i)).to be_empty
    end
  end
end
