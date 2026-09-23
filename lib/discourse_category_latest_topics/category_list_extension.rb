# frozen_string_literal: true

module ::DiscourseCategoryLatestTopics
  module CategoryListExtension
    def initialize(guardian = nil, options = {})
      super
      return unless DiscourseCategoryLatestTopics.active?

      displayed_categories = categories_with_descendants
      latest_topics =
        LatestTopicsQuery
          .new(
            guardian: @guardian,
            category_ids: displayed_categories.map(&:id),
            tag: @options[:tag],
          )
          .call
          .to_a

      @all_topics = [*@all_topics, *latest_topics]
      @dismissed_topic_users_lookup = nil
      find_user_data

      latest_topics.each do |topic|
        topic.include_last_poster = true
        topic.dismissed = dismissed_topic?(topic)
      end

      if latest_topics.present? && self.class.preloaded_topic_custom_fields.present?
        Topic.preload_custom_fields(latest_topics, self.class.preloaded_topic_custom_fields)
      end

      topics_by_category = latest_topics.group_by(&:category_latest_topic_category_id)
      displayed_categories.each do |category|
        category.category_latest_topics = topics_by_category.fetch(category.id, [])
      end
    end
  end
end
