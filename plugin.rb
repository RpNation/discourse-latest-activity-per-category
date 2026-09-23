# frozen_string_literal: true

# name: discourse-category-latest-topics
# about: Show the topic with the latest activity in each category row.
# version: 0.2.0
# authors: RpNation
# url: https://github.com/RpNation/discourse-category-latest-topics
# required_version: 2026.3.0

enabled_site_setting :discourse_category_latest_topics_enabled

module ::DiscourseCategoryLatestTopics
  PLUGIN_NAME = "discourse-category-latest-topics"
  PAGE_STYLE = "categories_with_latest_topics"

  def self.active?
    SiteSetting.discourse_category_latest_topics_enabled &&
      [SiteSetting.desktop_category_page_style, SiteSetting.mobile_category_page_style].include?(
        PAGE_STYLE,
      )
  end
end

require_relative "lib/discourse_category_latest_topics/engine"

after_initialize do
  reloadable_patch do
    ::CategoryPageStyle.singleton_class.prepend(DiscourseCategoryLatestTopics::PageStyleExtension)
    ::MobileCategoryPageStyle.singleton_class.prepend(
      DiscourseCategoryLatestTopics::PageStyleExtension,
    )
    ::Category.attr_accessor :category_latest_topics
    ::CategoryList.prepend(DiscourseCategoryLatestTopics::CategoryListExtension)
  end

  add_to_serializer(
    :category_detailed,
    :category_latest_topics,
    include_condition: -> { !object.category_latest_topics.nil? },
  ) do
    ActiveModel::ArraySerializer.new(
      object.category_latest_topics,
      each_serializer: ListableTopicSerializer,
      scope: scope,
      root: false,
    ).as_json
  end
end
