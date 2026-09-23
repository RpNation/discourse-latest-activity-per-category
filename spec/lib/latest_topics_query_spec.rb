# frozen_string_literal: true

RSpec.describe DiscourseCategoryLatestTopics::LatestTopicsQuery do
  fab!(:user)
  fab!(:category)

  describe "#call" do
    it "uses latest activity with a stable tie-break without giving pins priority" do
      Fabricate(:topic, category: category, bumped_at: 2.days.ago)
      tied = Fabricate(:topic, category: category, bumped_at: 1.day.ago)
      winner = Fabricate(:topic, category: category, bumped_at: tied.bumped_at)
      pinned = Fabricate(:topic, category: category, bumped_at: 2.days.ago, pinned_at: 1.hour.ago)
      Fabricate(
        :topic,
        category: category,
        bumped_at: 2.days.ago,
        pinned_at: 1.hour.ago,
        pinned_globally: true,
      )
      TopicUser.change(user.id, pinned.id, cleared_pinned_at: Time.current)

      result = described_class.new(guardian: user.guardian, category_ids: [category.id]).call

      expect(result.map(&:id)).to eq([winner.id])
    end

    it "includes local and global pins when their activity is newest, even after dismissal" do
      Fabricate(:topic, category: category, bumped_at: 3.days.ago)
      pinned = Fabricate(:topic, category: category, bumped_at: 1.day.ago, pinned_at: 1.hour.ago)
      global_pin =
        Fabricate(
          :topic,
          category: category,
          bumped_at: 2.days.ago,
          pinned_at: 1.hour.ago,
          pinned_globally: true,
        )

      result = described_class.new(guardian: user.guardian, category_ids: [category.id]).call
      expect(result.map(&:id)).to eq([pinned.id])

      TopicUser.change(user.id, pinned.id, cleared_pinned_at: Time.current)
      result = described_class.new(guardian: user.guardian, category_ids: [category.id]).call
      expect(result.map(&:id)).to eq([pinned.id])

      global_pin.update!(bumped_at: Time.current)
      TopicUser.change(user.id, global_pin.id, cleared_pinned_at: Time.current)
      result = described_class.new(guardian: user.guardian, category_ids: [category.id]).call
      expect(result.map(&:id)).to eq([global_pin.id])
    end

    it "excludes definitions, deleted topics, unlisted topics, messages, and shared drafts" do
      category_with_definition = Fabricate(:category_with_definition)
      winner = Fabricate(:topic, category: category_with_definition, bumped_at: 2.days.ago)
      definition = category_with_definition.topic
      definition.update_columns(pinned_at: nil, bumped_at: Time.current)
      Fabricate(:topic, category: category_with_definition, visible: false)
      Fabricate(:deleted_topic, category: category_with_definition)
      Fabricate(:private_message_topic)
      SiteSetting.shared_drafts_category = category.id.to_s
      Fabricate(:topic, category: category)

      result =
        described_class.new(
          guardian: user.guardian,
          category_ids: [category.id, category_with_definition.id],
        ).call

      expect(result.map(&:id)).to eq([winner.id])
    end

    it "includes accessible descendants and enforces private-category permissions before limiting" do
      child = Fabricate(:category, parent_category: category)
      public_topic = Fabricate(:topic, category: child, bumped_at: 1.day.ago)
      group = Fabricate(:group)
      private_child = Fabricate(:private_category, group: group, parent_category: category)
      private_topic = Fabricate(:topic, category: private_child)
      allowed_user = Fabricate(:user, groups: [group])

      public_result = described_class.new(guardian: Guardian.new, category_ids: [category.id]).call
      private_result =
        described_class.new(guardian: allowed_user.guardian, category_ids: [category.id]).call

      expect(public_result.map(&:id)).to eq([public_topic.id])
      expect(private_result.map(&:id)).to eq([private_topic.id])
    end

    it "respects topic, category, and tag mutes while retaining the next eligible candidate" do
      winner = Fabricate(:topic, category: category, bumped_at: 2.days.ago)
      muted_topic = Fabricate(:topic, category: category)
      TopicUser.change(
        user.id,
        muted_topic.id,
        notification_level: TopicUser.notification_levels[:muted],
      )
      tag = Fabricate(:tag)
      Fabricate(:topic, category: category, tags: [tag])
      TagUser.create!(user: user, tag: tag, notification_level: TagUser.notification_levels[:muted])
      child = Fabricate(:category, parent_category: category)
      Fabricate(:topic, category: child)
      CategoryUser.set_notification_level_for_category(
        user,
        CategoryUser.notification_levels[:muted],
        child.id,
      )

      result = described_class.new(guardian: user.guardian, category_ids: [category.id]).call

      expect(result.map(&:id)).to eq([winner.id])
    end

    it "respects anonymous default category and tag mutes" do
      winner = Fabricate(:topic, category: category, bumped_at: 2.days.ago)
      tag = Fabricate(:tag)
      SiteSetting.default_tags_muted = tag.name
      Fabricate(:topic, category: category, tags: [tag])
      child = Fabricate(:category, parent_category: category)
      Fabricate(:topic, category: child)
      SiteSetting.default_categories_muted = child.id.to_s

      result = described_class.new(guardian: Guardian.new, category_ids: [category.id]).call

      expect(result.map(&:id)).to eq([winner.id])
    end

    it "filters by the requested tag and handles empty category lists" do
      tag = Fabricate(:tag)
      winner = Fabricate(:topic, category: category, tags: [tag], bumped_at: 2.days.ago)
      Fabricate(:topic, category: category)

      result =
        described_class.new(
          guardian: user.guardian,
          category_ids: [category.id],
          tag: tag.name,
        ).call

      expect(result.map(&:id)).to eq([winner.id])
      expect(described_class.new(guardian: user.guardian, category_ids: []).call).to be_empty
    end

    it "finds nested descendants and keeps query count constant as displayed categories grow" do
      SiteSetting.max_category_nesting = 3
      child = Fabricate(:category, parent_category: category)
      grandchild = Fabricate(:category, parent_category: child)
      winner = Fabricate(:topic, category: grandchild)
      guardian = user.guardian
      described_class
        .new(guardian: guardian, category_ids: [category.id, child.id, grandchild.id])
        .call
        .to_a

      one_category_queries =
        track_sql_queries do
          described_class.new(guardian: guardian, category_ids: [category.id]).call.to_a
        end
      result = nil
      multiple_category_queries =
        track_sql_queries do
          result =
            described_class
              .new(guardian: guardian, category_ids: [category.id, child.id, grandchild.id])
              .call
              .to_a
        end

      expect(
        result.map { |topic| [topic.category_latest_topic_category_id, topic.id] },
      ).to contain_exactly(
        [category.id, winner.id],
        [child.id, winner.id],
        [grandchild.id, winner.id],
      )
      expect(multiple_category_queries.size).to eq(one_category_queries.size)
      expect(result.all? { |topic| topic.association(:last_poster).loaded? }).to eq(true)
    end
  end
end
